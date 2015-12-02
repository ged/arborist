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


	# The module that contains the default logic for invoking an external program
	# to do the work of a Monitor.
	module DefaultCallbacks

		### Given one or more +nodes+, return an Array of arguments that should be
		### appended to the external command.
		def exec_arguments( nodes )
			return []
		end


		### Write the specified +nodes+ as serialized data to the given +io+.
		def exec_input( nodes, io )
			return if io.closed?

			nodes.each do |node|
				self.log.debug "Serializing node properties for %s" % [ node.identifier ]
				prop_map = node.properties.collect do |key, val|
					"%s=%s" % [key, Shellwords.escape(val)]
				end

				self.log.debug "  writing %d properties to %p" % [ prop_map.size, io ]
				io.puts "%s %s" % [ node.identifier, prop_map.join(' ') ]
				self.log.debug "  wrote the node to FD %d" % [ io.fileno ]
			end

			self.log.debug "done writing to FD %d" % [ io.fileno ]
		end


		### Return the results of running the external command
		def handle_results( pid, out, err )
			err.flush
			err.close
			self.log.debug "Closed child's stderr."

		    # identifier key1=val1 key2=val2
			results = out.each_line.with_object({}) do |line, accum|
				identifier, attributes = line.split( ' ', 2 )
				attrhash = Shellwords.shellsplit( attributes ).each_with_object({}) do |pair, hash|
					key, val = pair.split( '=', 2 )
					hash[ key ] = val
				end

				accum[ identifier ] = attrhash
			end
			out.close

			self.log.debug "Waiting on PID %d" % [ pid ]
			Process.waitpid( pid )

			return results
		end

	end # module DefaultCallbacks


	# An object class for creating a disposable binding in which to run the exec
	# callbacks.
	class RunContext
		extend Loggability
		log_to :arborist
		include DefaultCallbacks
	end # class RunContext



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
		paths = if path.directory?
				Pathname.glob( directory + NODE_FILE_PATTERN )
			else
				[ path ]
			end

		return paths.flat_map do |file|
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

		@exec_command = nil
		@exec_block = nil
		@exec_callbacks_mod = Module.new

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
	attr_accessor :exec_command

	##
	# The callback to invoke when the monitor is run.
	attr_accessor :exec_block

	##
	# The monitor's execution callbacks contained in a Module
	attr_accessor :exec_callbacks_mod

	##
	# The path to the source this Monitor was loaded from, if applicable
	attr_accessor :source


	### Run the monitor
	def run( nodes )
		if self.exec_block
			return self.exec_block.call( nodes )
		elsif self.exec_command
			command = self.exec_command
			return self.run_external_command( command, nodes )
		end
	end


	### Run the external +command+ against the specified +nodes+.
	def run_external_command( command, nodes )
		self.log.debug "Running external command %p for %d nodes" % [ command, nodes.size ]
		context = Arborist::Monitor::RunContext.new
		context.extend( self.exec_callbacks_mod ) if self.exec_callbacks_mod

		arguments = Array( context.exec_arguments(nodes) )
		command += arguments.flatten( 1 )
		self.log.debug "  command after adding arguments: %p" % [ command ]

		child_stdin, parent_writer = IO.pipe
		parent_reader, child_stdout = IO.pipe
		parent_err_reader, child_stderr = IO.pipe

		self.log.debug "Spawning command: %s" % [ Shellwords.join(command) ]
        pid = Process.spawn( *command, out: child_stdout, in: child_stdin, err: child_stderr )

        child_stdout.close
        child_stdin.close
		child_stderr.close

		context.exec_input( nodes, parent_writer )
		parent_writer.close

		return context.handle_results( pid, parent_reader, parent_err_reader )
	ensure
		if pid
			begin
				Process.kill( 0, pid ) # waitpid if it's still alive
				Process.waitpid( pid )
			rescue Errno::ESRCH
			end
		end
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


	### Specify what should be run to do the actual monitoring. Accepts an Array of strings
	### (which are passed to `spawn`), a block, or a Module that implements a #run method.
	def exec( *command, &block )
		unless command.empty?
			self.log.warn "Ignored block with exec %s (%p)" % [ command.first, block ] if block

			case command.first
			when Module
				@exec_block = command.first.method( :run )
			when String
				@exec_command = command
			else
				raise ArgumentError, "don't know how to handle command: %p" % [ command ]
			end

			return
		end
		@exec_block = block
	end


	### Declare an argument-building callback for the command run by 'exec'. The +block+
	### should accept an Array of nodes and return an Array of arguments for the command.
	def exec_arguments( &block )
		self.exec_callbacks_mod.instance_exec( block ) do |method_body|
			define_method( :exec_arguments, &method_body )
		end
	end


	### Declare an input-building callback for the command run by 'exec'. The +block+
	### should accept an Array of nodes and a writable IO object, and should write out
	### the necessary input to drive the command to the IO.
	def exec_input( &block )
		self.exec_callbacks_mod.instance_exec( block ) do |method_body|
			define_method( :exec_input, &method_body )
		end
	end


	### Declare a results handler +block+ that will be used to parse the results for
	### external commands. The block should accept 2 or 3 arguments: a PID, an IO that will
	### be opened to the command's STDOUT, and optionally an IO that will be opened to the
	### command's STDERR.
	def handle_results( &block )
		self.exec_callbacks_mod.instance_exec( block ) do |method_body|
			define_method( :handle_results, &method_body )
		end
	end


	### Set the module to use for the callbacks when interacting with the executed
	### external command.
	def exec_callbacks( mod )
		self.exec_callbacks_mod = mod
	end

end # class Arborist::Monitor
