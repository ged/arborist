# -*- ruby -*-
#encoding: utf-8

require 'securerandom'
require 'pathname'
require 'tempfile'
require 'configurability'
require 'loggability'
require 'rbczmq'

require 'arborist' unless defined?( Arborist )
require 'arborist/node'
require 'arborist/mixins'


# The main Arborist process -- responsible for coordinating all other activity.
class Arborist::Manager
	extend Configurability,
		   Loggability,
	       Arborist::MethodUtilities

	# Signals the manager responds to
	QUEUE_SIGS = [
		:INT, :TERM, :HUP, :USR1,
		# :TODO: :QUIT, :WINCH, :USR2, :TTIN, :TTOU
	]

	# The number of seconds to wait between checks for incoming signals
	SIGNAL_INTERVAL = 0.5

	# Configurability API -- set config defaults
	CONFIG_DEFAULTS = {
		state_file: nil,
		checkpoint_frequency: 30000,
		heartbeat_frequency: 1000,
		linger: 5000
	}


	# Use the Arborist logger
	log_to :arborist

	# Configurability API -- use the 'arborist' section
	config_key :arborist


	##
	# The Pathname of the file the manager's node tree state is saved to
	singleton_attr_accessor :state_file

	##
	# The number of milliseconds between automatic state checkpoints
	singleton_attr_accessor :checkpoint_frequency

	##
	# The number of milliseconds between heartbeat events
	singleton_attr_accessor :heartbeat_frequency

	##
	# The maximum amount of time to wait for pending events to be delivered during
	# shutdown, in milliseconds.
	singleton_attr_accessor :linger


	### Configurability API -- configure the manager
	def self::configure( config=nil )
		config = self.defaults.merge( config || {} )
		self.log.debug "Config is: %p" % [ config ]

		self.state_file = config[:state_file] && Pathname( config[:state_file] )
		self.linger = config[:linger].to_i
		self.log.info "Linger configured to %p" % [ self.linger ]

		self.heartbeat_frequency = config[:heartbeat_frequency].to_i ||
			CONFIG_DEFAULTS[:heartbeat_frequency]
		raise Arborist::ConfigError, "heartbeat frequency must be a positive non-zero integer" if
			self.heartbeat_frequency <= 0

		interval = config[:checkpoint_frequency].to_i
		if interval && interval.nonzero?
			self.checkpoint_frequency = interval
		else
			self.checkpoint_frequency = nil
		end
	end


	#
	# Instance methods
	#

	### Create a new Arborist::Manager.
	def initialize
		@run_id = SecureRandom.hex( 16 )
		@root = Arborist::Node.create( :root )
		@nodes = { '_' => @root }

		@subscriptions = {}
		@tree_built = false

		@tree_sock = @event_sock = nil
		@signal_timer = nil
		@start_time   = nil

		@checkpoint_timer = nil
		@linger = self.class.linger || Arborist::Manager::CONFIG_DEFAULTS[ :linger ]
		self.log.info "Linger set to %p" % [ @linger ]

		@zmq_loop = ZMQ::Loop.new
		# @zmq_loop.verbose = true
		@tree_sock = self.setup_tree_socket
		@event_sock = self.setup_event_socket

		@api_handler = Arborist::Manager::TreeAPI.new( @tree_sock, self )
		@tree_sock.handler = @api_handler
		@zmq_loop.register( @tree_sock )

		@event_publisher = Arborist::Manager::EventPublisher.new( @event_sock, self, @zmq_loop )
		@event_sock.handler = @event_publisher
		@zmq_loop.register( @event_sock )

		@heartbeat_timer = self.make_heartbeat_timer
		@checkpoint_timer = self.make_checkpoint_timer

		Thread.main[:signal_queue] = []
	end


	######
	public
	######

	##
	# A unique string used to identify different runs of the Manager
	attr_reader :run_id

	##
	# The root node of the tree.
	attr_accessor :root

	##
	# The Hash of all loaded Nodes, keyed by their identifier
	attr_accessor :nodes

	##
	# The Hash of all Subscriptions, keyed by their subscription ID
	attr_accessor :subscriptions

	##
	# The time at which the manager began running.
	attr_accessor :start_time

	##
	# The ZMQ::Handler that manages the IO for the Tree API
	attr_reader :api_handler

	##
	# The ZMQ::Handler that manages the IO for the event-publication API.
	attr_reader :event_publisher

	##
	# The ZMQ::Loop that will/is acting as the main loop.
	attr_reader :zmq_loop

	##
	# Flag for marking when the tree is built successfully the first time
	attr_predicate_accessor :tree_built

	##
	# The maximum amount of time to wait for pending events to be delivered during
	# shutdown, in milliseconds.
	attr_reader :linger

	##
	# The ZMQ::Timer that processes signals
	attr_reader :signal_timer

	##
	# The ZMQ::Timer that periodically checkpoints the manager's state (if it's configured to do so)
	attr_reader :checkpoint_timer

	##
	# The ZMQ::Timer that periodically publishes a heartbeat event
	attr_reader :heartbeat_timer


	#
	# :section: Startup/Shutdown
	#

	### Setup sockets and start the event loop.
	def run
		self.log.info "Getting ready to start the manager."
		self.publish_system_event( 'startup', start_time: Time.now.to_s, version: Arborist::VERSION )
		self.register_timers
		self.set_signal_handlers
		self.start_accepting_requests

		return self # For chaining
	ensure
		self.restore_signal_handlers
		if self.zmq_loop
			self.log.debug "Unregistering sockets."
			self.zmq_loop.remove( @tree_sock )
			@tree_sock.pollable.close
			self.zmq_loop.remove( @event_sock )
			@event_sock.pollable.close
			self.zmq_loop.cancel_timer( @checkpoint_timer ) if @checkpoint_timer
		end

		self.save_node_states

		self.log.debug "Resetting ZMQ context"
		Arborist.reset_zmq_context
	end


	### Returns true if the Manager is running.
	def running?
		return self.zmq_loop && self.zmq_loop.running?
	end


	### Register the Manager's timers.
	def register_timers
		self.zmq_loop.register_timer( self.heartbeat_timer )
		self.zmq_loop.register_timer( self.checkpoint_timer ) if self.checkpoint_timer
	end


	### Start a loop, accepting a request and handling it.
	def start_accepting_requests
		self.log.debug "Starting the main loop"

		self.setup_signal_timer
		self.start_time = Time.now

		self.log.debug "Manager running."
		return self.zmq_loop.start
	end


	### Set up the ZMQ REP socket for the Tree API.
	def setup_tree_socket
		sock = Arborist.zmq_context.socket( :REP )
		self.log.debug "  binding the tree API socket (%#0x) to %p" %
			[ sock.object_id * 2, Arborist.tree_api_url ]
		sock.linger = 0
		sock.bind( Arborist.tree_api_url )
		return ZMQ::Pollitem.new( sock, ZMQ::POLLIN|ZMQ::POLLOUT )
	end


	### Set up the ZMQ PUB socket for published events.
	def setup_event_socket
		sock = Arborist.zmq_context.socket( :PUB )
		self.log.debug "  binding the event socket (%#0x) to %p" %
			[ sock.object_id * 2, Arborist.event_api_url ]
		sock.linger = self.linger
		sock.bind( Arborist.event_api_url )
		return ZMQ::Pollitem.new( sock, ZMQ::POLLOUT )
	end


	### Restart the manager
	def restart
		raise NotImplementedError
	end


	### Stop the manager.
	def stop
		self.log.info "Stopping the manager."
		self.ignore_signals
		self.cancel_signal_timer

		@api_handler.shutdown
		@event_publisher.shutdown

		self.zmq_loop.stop
	end


	#
	# :section: Node state saving/reloading
	#

	### Write out the state of all the manager's nodes to the state_file if one is
	### configured.
	def save_node_states
		path = self.class.state_file or return
		self.log.info "Saving current node state to %s" % [ path ]
		tmpfile = Tempfile.create(
			[path.basename.to_s.sub(path.extname, ''), path.extname],
			path.dirname.to_s,
			encoding: 'binary'
		)
		Marshal.dump( self.nodes, tmpfile )
		tmpfile.close

		File.rename( tmpfile.path, path.to_s )

	rescue SystemCallError => err
		self.log.error "%p while saving node state: %s" % [ err.class, err.message ]

	ensure
		File.unlink( tmpfile.path ) if tmpfile && File.exist?( tmpfile.path )
	end


	### Attempt to restore the state of loaded node from the configured state file. Returns
	### true if it succeeded, or false if a state file wasn't configured, doesn't
	### exist, isn't readable, or couldn't be unmarshalled.
	def restore_node_states
		path = self.class.state_file or return false
		return false unless path.readable?

		self.log.info "Restoring node state from %s" % [ path ]
		nodes = Marshal.load( path.open('r:binary') )

		nodes.each do |identifier, saved_node|
			self.log.debug "Loaded node: %p" % [ identifier ]
			if (( current_node = self.nodes[ identifier ] ))
				self.log.debug "Restoring state of the %p node." % [ identifier ]
				current_node.restore( saved_node )
			else
				self.log.info "Not restoring state for the %s node: not present in the loaded tree." %
					[ identifier ]
			end
		end

		return true
	end


	### Make a ZMQ::Timer that will publish a heartbeat event at a configurable interval.
	def make_heartbeat_timer
		interval = self.class.heartbeat_frequency || CONFIG_DEFAULTS[ :heartbeat_frequency ]

		self.log.info "Setting up to heartbeat every %dms" % [ interval ]
		heartbeat_timer = ZMQ::Timer.new( (interval/1000.0), 0 ) do
			self.publish_heartbeat_event
		end
		return heartbeat_timer
	end


	### Make a ZMQ::Timer that will save a snapshot of the node tree's state to the state
	### file on a configured interval if it's configured.
	def make_checkpoint_timer
		return nil unless self.class.state_file
		interval = self.class.checkpoint_frequency or return nil

		self.log.info "Setting up node state checkpoint every %dms" % [ interval ]
		checkpoint_timer = ZMQ::Timer.new( (interval/1000.0), 0 ) do
			self.save_node_states
		end
		return checkpoint_timer
	end


	#
	# :section: Signal Handling
	# These methods set up some behavior for starting, restarting, and stopping
	# your application when a signal is received. If you don't want signals to
	# be handled, override #set_signal_handlers with an empty method.
	#

	### Set up a periodic ZMQ timer to check for queued signals and handle them.
	def setup_signal_timer
		@signal_timer = ZMQ::Timer.new( SIGNAL_INTERVAL, 0, self.method(:process_signal_queue) )
		self.zmq_loop.register_timer( @signal_timer )
	end


	### Disable the timer that checks for incoming signals
	def cancel_signal_timer
		if self.signal_timer
			self.signal_timer.cancel
			self.zmq_loop.cancel_timer( self.signal_timer )
		end
	end


	### Set up signal handlers for common signals that will shut down, restart, etc.
	def set_signal_handlers
		self.log.debug "Setting up deferred signal handlers."
		QUEUE_SIGS.each do |sig|
			Signal.trap( sig ) { Thread.main[:signal_queue] << sig }
		end
	end


	### Set all signal handlers to ignore.
	def ignore_signals
		self.log.debug "Ignoring signals."
		QUEUE_SIGS.each do |sig|
			Signal.trap( sig, :IGNORE )
		end
	end


	### Set the signal handlers back to their defaults.
	def restore_signal_handlers
		self.log.debug "Restoring default signal handlers."
		QUEUE_SIGS.each do |sig|
			Signal.trap( sig, :DEFAULT )
		end
	end


	### Handle any queued signals.
	def process_signal_queue
		# Look for any signals that arrived and handle them
		while sig = Thread.main[:signal_queue].shift
			self.handle_signal( sig )
		end
	end


	### Handle signals.
	def handle_signal( sig )
		self.log.debug "Handling signal %s" % [ sig ]
		case sig
		when :INT, :TERM
			self.on_termination_signal( sig )

		when :HUP
			self.on_hangup_signal( sig )

		when :USR1
			self.on_user1_signal( sig )

		else
			self.log.warn "Unhandled signal %s" % [ sig ]
		end

	end


	### Handle a TERM signal. Shuts the handler down after handling any current request/s. Also
	### aliased to #on_interrupt_signal.
	def on_termination_signal( signo )
		self.log.warn "Terminated (%p)" % [ signo ]
		self.stop
	end
	alias_method :on_interrupt_signal, :on_termination_signal


	### Handle a HUP signal. The default is to restart the handler.
	def on_hangup_signal( signo )
		self.log.warn "Hangup (%p)" % [ signo ]
		self.restart
	end


	### Handle a USR1 signal. Writes a message to the log.
	def on_user1_signal( signo )
		self.log.info "Checkpoint: User signal."
		self.save_node_states
	end


	### Simulate the receipt of the specified +signal+ (probably only useful
	### in testing).
	def simulate_signal( signal )
		Thread.main[:signal_queue] << signal.to_sym
	end


	#
	# :section: Tree API
	#

	### Add nodes yielded from the specified +enumerator+ into the manager's
	### tree.
	def load_tree( enumerator )
		enumerator.each do |node|
			self.add_node( node )
		end
		self.build_tree
	end


	### Build the tree out of all the loaded nodes.
	def build_tree
		self.log.info "Building tree from %d loaded nodes." % [ self.nodes.length ]

		# Build primary tree structure
		self.nodes.each_value do |node|
			next if node.operational?
			self.link_node_to_parent( node )
		end
		self.tree_built = true

		# Set up secondary dependencies
		self.nodes.each_value do |node|
			node.register_secondary_dependencies( self )
		end

		self.restore_node_states
	end


	### Link the specified +node+ to its parent. Raises an error if the specified +node+'s
	### parent is not yet loaded.
	def link_node_to_parent( node )
		self.log.debug "Linking node %p to its parent" % [ node ]
		parent_id = node.parent || '_'
		parent_node = self.nodes[ parent_id ] or
			raise "no parent '%s' node loaded for %p" % [ parent_id, node ]

		self.log.debug "adding %p as a child of %p" % [ node, parent_node ]
		parent_node.add_child( node )
	end


	### Add the specified +node+ to the Manager.
	def add_node( node )
		identifier = node.identifier

		unless self.nodes[ identifier ].equal?( node )
			self.remove_node( self.nodes[identifier] )
			self.nodes[ identifier ] = node
		end

		if self.tree_built?
			self.link_node( node )
			self.publish_system_event( 'node_added', node: identifier )
		end
	end


	### Link the node to other nodes in the tree.
	def link_node( node )
		raise "Tree is not built yet" unless self.tree_built?

		self.link_node_to_parent( node )
		node.register_secondary_dependencies( self )
	end


	### Remove a +node+ from the Manager. The +node+ can either be the Arborist::Node to
	### remove, or the identifier of a node.
	def remove_node( node )
		node = self.nodes[ node ] unless node.is_a?( Arborist::Node )
		return unless node

		raise "Can't remove an operational node" if node.operational?

		self.log.info "Removing node %p" % [ node ]
		self.publish_system_event( 'node_removed', node: node.identifier )
		node.children.each do |identifier, child_node|
			self.remove_node( child_node )
		end

		if parent_node = self.nodes[ node.parent || '_' ]
			parent_node.remove_child( node )
		end

		return self.nodes.delete( node.identifier )
	end


	### Update the node with the specified +identifier+ with the given +new_properties+
	### and propagate any events generated by the update to the node and its ancestors.
	def update_node( identifier, new_properties )
		unless (( node = self.nodes[identifier] ))
			self.log.warn "Update for non-existent node %p ignored." % [ identifier ]
			return []
		end

		events = node.update( new_properties )
		self.propagate_events( node, events )
	end


	### Traverse the node tree and fetch the specified +return_values+ from any nodes which
	### match the given +filter+, skipping downed nodes and all their children
	### unless +include_down+ is set. If +return_values+ is set to +nil+, then all
	### values from the node will be returned.
	def fetch_matching_node_states( filter, return_values, include_down=false, negative_filter={} )
		nodes_iter = if include_down
				self.all_nodes
			else
				self.reachable_nodes
			end

		states = nodes_iter.
			select {|node| node.matches?(filter) }.
			reject {|node| !negative_filter.empty? && node.matches?(negative_filter) }.
			each_with_object( {} ) do |node, hash|
				hash[ node.identifier ] = node.fetch_values( return_values )
			end

		return states
	end


	### Return the duration the manager has been running in seconds.
	def uptime
		return 0 unless self.start_time
		return Time.now - self.start_time
	end


	### Return the number of nodes in the manager's tree.
	def nodecount
		return self.nodes.length
	end


	### Return an Array of the identifiers of all nodes in the manager's tree.
	def nodelist
		return self.nodes.keys
	end


	#
	# Tree-traversal API
	#


	### Return the current root node.
	def root_node
		return self.nodes[ '_' ]
	end


	### Yield each node in a depth-first traversal of the manager's tree
	### to the specified +block+, or return an Enumerator if no block is given.
	def all_nodes( &block )
		iter = self.enumerator_for( self.root )
		return iter.each( &block ) if block
		return iter
	end


	### Yield each node that is not down to the specified +block+, or return
	### an Enumerator if no block is given.
	def reachable_nodes( &block )
		iter = self.enumerator_for( self.root ) {|node| node.reachable? }
		return iter.each( &block ) if block
		return iter
	end


	### Return an enumerator for the specified +start_node+.
	def enumerator_for( start_node, &filter )
		return Enumerator.new do |yielder|
			traverse = ->( node ) do
				if !filter || filter.call( node )
					yielder.yield( node )
					node.each( &traverse )
				end
			end
			traverse.call( start_node )
		end
	end


	### Return a +depth+ limited enumerator for the specified +start_node+.
	def depth_limited_enumerator_for( start_node, depth, &filter )
		return Enumerator.new do |yielder|
			traverse = ->( node, current_depth ) do
				self.log.debug "Enumerating nodes from %s at depth: %p" %
					[ node.identifier, current_depth ]

				if !filter || filter.call( node )
					yielder.yield( node )
					node.each do |child|
						traverse[ child, current_depth - 1 ]
					end if current_depth > 0
				end
			end
			traverse.call( start_node, depth )
		end
	end


	### Return an Array of all nodes below the specified +node+.
	def descendants_for( node )
		return self.enumerator_for( node ).to_a
	end


	### Return the Array of all nodes above the specified +node+.
	def ancestors_for( node )
		parent_id = node.parent or return []
		parent = self.nodes[ parent_id ]
		return [ parent ] + self.ancestors_for( parent )
	end


	#
	# Event API
	#

	### Add the specified +subscription+ to the node corresponding with the given +identifier+.
	def subscribe( identifier, subscription )
		identifier ||= '_'
		node = self.nodes[ identifier ] or raise ArgumentError, "no such node %p" % [ identifier ]

		self.log.debug "Registering subscription %p" % [ subscription ]
		node.add_subscription( subscription )
		self.log.debug " adding '%s' to the subscriptions hash." % [ subscription.id ]
		self.subscriptions[ subscription.id ] = node
		self.log.debug "  subscriptions hash: %#0x" % [ self.subscriptions.object_id ]
	end


	### Publish a system event that observers can watch for to detect restarts.
	def publish_heartbeat_event
		self.publish_system_event( 'heartbeat', run_id: self.run_id )
	end


	### Publish an event with the specified +eventname+ and +data+.
	def publish_system_event( eventname, **data )
		eventname = eventname.to_s
		eventname = 'sys.' + eventname unless eventname.start_with?( 'sys.' )
		self.log.debug "Publishing %s event: %p." % [ eventname, data ]
		self.event_publisher.publish( eventname, data )
	end


	### Create a subscription that publishes to the Manager's event publisher for
	### the node with the specified +identifier+ and +event_pattern+, using the
	### given +criteria+ when considering an event.
	def create_subscription( identifier, event_pattern, criteria, negative_criteria={} )
		sub = Arborist::Subscription.new( event_pattern, criteria, negative_criteria ) do |*args|
			self.event_publisher.publish( *args )
		end
		self.subscribe( identifier, sub )

		return sub
	end


	### Remove the subscription with the specified +subscription_identifier+ from the node
	### it's attached to and from the manager, and return it.
	def remove_subscription( subscription_identifier )
		node = self.subscriptions.delete( subscription_identifier ) or return nil
		return node.remove_subscription( subscription_identifier )
	end


	### Propagate one or more +events+ to the specified +node+ and its ancestors in the tree,
	### publishing them to matching subscriptions belonging to the nodes along the way.
	def propagate_events( node, *events )
		node.publish_events( *events )

		if node.parent
			self.log.debug "Propagating %d events from %s -> %s" % [
				events.length,
				node.identifier,
				node.parent
			]
			parent = self.nodes[ node.parent ] or raise "couldn't find parent %p of node %p!" %
				[ node.parent, node.identifier ]
			self.propagate_events( parent, *events )
		end
	end


	require 'arborist/manager/tree_api'
	require 'arborist/manager/event_publisher'

end # class Arborist::Manager
