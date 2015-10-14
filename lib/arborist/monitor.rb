# -*- ruby -*-
#encoding: utf-8

require 'shellwords'
require 'arborist' unless defined?( Arborist )
require 'arborist/mixins'

using Arborist::TimeRefinements


# A declaration of an action to run against Manager nodes to update their state.
class Arborist::Monitor
	extend Loggability,
	       Arborist::MethodUtilities

	# Loggability API -- write logs to the Arborist log host
	log_to :arborist


	##
	# The key for the thread local that is used to track instances as they're
	# loaded.
	LOADED_INSTANCE_KEY = :loaded_monitor_instances

	##
	# The glob pattern to use for searching for monitors
	NODE_FILE_PATTERN = '**/*.rb'

	##
	# The default monitoring interval, in seconds
	DEFAULT_INTERVAL = 5.minutes

	##
	# The default number of seconds to defer startup to splay common intervals
	DEFAULT_SPLAY = 0


	Arborist.add_dsl_constructor( :Monitor ) do |description, &block|
		Arborist::Monitor.new( description, &block )
	end


	### Overridden to track instances of created nodes for the DSL.
	def self::new( * )
		new_instance = super
		Arborist::Monitor.add_loaded_instance( new_instance )
		return new_instance
	end


	### Record a new loaded instance if the Thread-local variable is set up to track
	### them.
	def self::add_loaded_instance( new_instance )
		instances = Thread.current[ LOADED_INSTANCE_KEY ] or return
		instances << new_instance
	end


	### Load the specified +file+ and return any new Nodes created as a result.
	def self::load( file )
		self.log.info "Loading monitor file %s..." % [ file ]
		Thread.current[ LOADED_INSTANCE_KEY ] = []
		Kernel.load( file )
		return Thread.current[ LOADED_INSTANCE_KEY ]
	ensure
		Thread.current[ LOADED_INSTANCE_KEY ] = nil
	end


	### Return an iterator for all the monitor files in the specified +directory+.
	def self::each_in( directory )
		path = Pathname( directory )
		iter = if path.directory?
				Pathname.glob( directory + NODE_FILE_PATTERN ).lazy.flat_map
			else
				[ path ]
			end

		return iter.lazy.flat_map do |file|
			file_url = "file://%s" % [ file.expand_path ]
			monitors = self.load( file )
			self.log.debug "Loaded monitors %p..." % [ monitors ]
			monitors.each do |monitor|
				monitor.source = file_url
			end
			monitors
		end
	end


	### Create a new Monitor with the specified +description+. If the +block+ is
	### given, it will be evaluated in the context of the new Monitor before it's
	### returned.
	def initialize( description, &block )
		@description = description
		@interval = DEFAULT_INTERVAL
		@splay = DEFAULT_SPLAY

		@positive_criteria = {}
		@negative_criteria = {}
		@include_down = false
		@node_properties = []

		@run_command = nil
		@run_callback = nil

		@source = nil

		self.instance_exec( &block ) if block
	end


	######
	public
	######

	##
	# The object's description
	attr_accessor :description

	##
	# The interval between runs in seconds, as set by `every`.
	attr_writer :interval

	##
	# The number of seconds of splay to use when running the monitor.
	attr_writer :splay

	##
	# A Hash of criteria to pass to the Manager when searching for nodes to monitor.
	attr_reader :positive_criteria

	##
	# A Hash of criteria to pass to the Manager to filter out nodes to monitor.
	attr_reader :negative_criteria

	##
	# Flag for whether the monitor will include downed hosts in its search. Defaults
	# to +false+.
	attr_predicate :include_down

	##
	# The list of node properties to include when running the monitor.
	attr_reader :node_properties

	##
	# The shell command to exec when running the monitor (if any). This can be
	# any valid arguments to the `Kernel.spawn` method.
	attr_accessor :run_command

	##
	# The callback to wrap runs of the `run_command` in (if any). This can be any object
	# that responds to #call.
	attr_accessor :run_callback

	##
	# The path to the source this Monitor was loaded from, if applicable
	attr_accessor :source


	### Run the monitor
	def run( nodes )
		callback = self.run_callback
		command = self.run_command

		if command
			return self.run_with_external_command( nodes, command, callback )
		elsif callback
			return callback.call( nodes )
		else
			raise "Nothing to run! (expected one or both of run callback or command to be set)"
		end
	end


	### Run the external +command+, wrapping it either in the provided +callback+, or if
	### a callback isn't provided, in the #default_run_callback.
	def run_with_external_command( nodes, command, callback=nil )
		callback ||= self.method( :default_run_callback )

		# write each node to the pipe
		pid = nil
		updates = callback.call( nodes ) do |*additional_args|
			command += additional_args.flatten( 1 )

            parent_reader, child_writer = IO.pipe
            child_reader, parent_writer = IO.pipe

			self.log.debug "Spawning command: %s" % [ Shellwords.join(command) ]
            pid = Process.spawn( *command, out: child_writer, in: child_reader, close_others: true )
            child_writer.close
            child_reader.close

			yield( parent_writer ) if block_given?

			parent_writer.close
			output = parent_reader.read
			self.log.debug "Raw output: %p" % [ output ]
			output
		end

		# wait on the pid
		if pid
			self.log.debug "Waiting on PID %d" % [ pid ]
			Process.waitpid( pid )
		end

		return updates
	end


	### Specify that the monitor should be run every +seconds+ seconds.
	def every( seconds=nil )
		@interval = seconds if seconds
		return @interval
	end
	alias_method :interval, :every


	### Specify the number of seconds of interval splay that should be used when
	### running the monitor.
	def splay( seconds=nil )
		@splay = seconds if seconds
		return @splay
	end


	### Specify that the monitor should include the specified +criteria+ when searching
	### for nodes it will run against.
	def match( criteria )
		@positive_criteria.merge!( criteria )
	end


	### Specify that the monitor should exclude nodes which match the specified
	### +criteria+ when searching for nodes it will run against.
	def exclude( criteria )
		@negative_criteria.merge!( criteria )
	end


	### Specify that the monitor should (or should not) include nodes which have been
	### marked 'down'.
	def include_down( flag=nil )
		@include_down = flag unless flag.nil?
		return @include_down
	end


	### Specify properties from each node to provide to the monitor.
	def use( *properties )
		@node_properties = properties
	end


	### Specify what should be run to do the actual monitoring.
	def exec( *command, &block )
		@run_command = command unless command.empty?
		@run_callback = block
	end


	#########
	protected
	#########

	### The callback block that is wrapped around the command-only form of monitor.
	def default_run_callback( nodes, &runner )
		node_data = self.serialize_node_list( nodes )

		serialized_results = runner.call do |writer|
			writer.puts node_data
		end

		return self.deserialize_node_data( serialized_results )
	end


	### Return the given Hash of +node+ property hashes, keyed by identifier, as a String
	### of node data, one line per identifier.
	def serialize_node_list( nodes )
		return nodes.each_with_object( '' ) do |(identifier, properties), buffer|
			prop_map = properties.collect {|key, val| "%s=%s" % [key, Shellwords.escape(val)] }
			buffer <<
				identifier <<
				prop_map.join( ' ' ) <<
				"\n"
		end
	end


	### Return a copy of the specified +string+, unescaping any shell-escaped
	### characters.
	def shellwords_unescape( string )
		return '' if string == "''"
		return string.
			sub( %r{(?!<\\)(?<quote>["'`])(.*?)(?!<\\)\k<quote>}, '\2' ).
			gsub( %r{\\([^A-Za-z0-9_\-.,:/@\n])}, '\1' ).
			gsub( "\\\n", '' )
	end

end # class Arborist::Monitor
