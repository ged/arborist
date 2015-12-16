# -*- ruby -*-
#encoding: utf-8

require 'arborist' unless defined?( Arborist )


# The Arborist entity responsible for observing changes to the tree and
# reporting on them.
class Arborist::Observer
	extend Loggability,
	       Arborist::MethodUtilities

	# Loggability API -- write logs to the Arborist log host
	log_to :arborist


	autoload :Action, 'arborist/observer/action'
	autoload :Summarize, 'arborist/observer/summarize'


	##
	# The key for the thread local that is used to track instances as they're
	# loaded.
	LOADED_INSTANCE_KEY = :loaded_observer_instances

	##
	# The glob pattern to use for searching for observers
	OBSERVER_FILE_PATTERN = '**/*.rb'


	Arborist.add_dsl_constructor( :Observer ) do |description, &block|
		Arborist::Observer.new( description, &block )
	end



	### Overridden to track instances of created nodes for the DSL.
	def self::new( * )
		new_instance = super
		Arborist::Observer.add_loaded_instance( new_instance )
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
		self.log.info "Loading observer file %s..." % [ file ]
		Thread.current[ LOADED_INSTANCE_KEY ] = []
		Kernel.load( file )
		return Thread.current[ LOADED_INSTANCE_KEY ]
	ensure
		Thread.current[ LOADED_INSTANCE_KEY ] = nil
	end


	### Return an iterator for all the observer files in the specified +directory+.
	def self::each_in( directory )
		path = Pathname( directory )
		paths = if path.directory?
				Pathname.glob( directory + OBSERVER_FILE_PATTERN )
			else
				[ path ]
			end

		return paths.flat_map do |file|
			file_url = "file://%s" % [ file.expand_path ]
			observers = self.load( file )
			self.log.debug "Loaded observers %p..." % [ observers ]
			observers.each do |observer|
				observer.source = file_url
			end
			observers
		end
	end


	### Create a new Observer with the specified +description+.
	def initialize( description, &block )
		@description = description
		@subscriptions = []
		@actions = []

		self.instance_exec( &block ) if block
	end


	######
	public
	######

	##
	# The observer's description
	attr_reader :description

	##
	# The observer's actions
	attr_reader :actions

	##
	# The source file the observer was loaded from
	attr_accessor :source


	#
	# DSL Methods
	#

	### Specify a pattern for events the observer is interested in. Options:
	### to::
	###   the name of the event; defaults to every event type
	### where::
	###   a Hash of criteria to match against event data
	### on::
	###   the identifier of the node to subscribe on, defaults to the root node
	##    which receives all node events.
	def subscribe( to: nil, where: {}, on: nil )
		@subscriptions << { criteria: where, identifier: on, event_type: to }
	end


	### Register an action that will be taken when a subscribed event is received.
	def action( options={}, &block )
		@actions << Arborist::Observer::Action.new( options, &block )
	end


	### Register a summary action.
	def summarize( options={}, &block )
		@actions << Arborist::Observer::Summarize.new( options, &block )
	end


	#
	# Observe Methods
	#

	### Fetch the descriptions of which events this Observer would like to receive. If no
	### subscriptions have been specified, a subscription that will match any event is returned.
	def subscriptions

		# Subscribe to all events if there are no subscription criteria.
		self.subscribe if @subscriptions.empty?

		return @subscriptions
	end


	### Handle a published event.
	def handle_event( uuid, event )
		self.actions.each do |action|
			action.handle_event( event )
		end
	end


	### Return an Array of timer callbacks of the form:
	###
	###   [ interval_seconds, callable ]
	###
	def timers
		return self.actions.map do |action|
			next nil unless action.respond_to?( :on_timer ) &&
				action.time_threshold.nonzero?
			[ action.time_threshold, action.method(:on_timer) ]
		end.compact
	end

end # class Arborist::Observer
