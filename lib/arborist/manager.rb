# -*- ruby -*-
#encoding: utf-8

require 'pathname'
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


	##
	# Use the Arborist logger
	log_to :arborist


	#
	# Instance methods
	#

	### Create a new Arborist::Manager.
	def initialize
		@root = Arborist::Node.create( :root )
		@nodes = {
			'_' => @root,
		}
		@subscriptions = {}
		@tree_built = false

		@tree_sock = @event_sock = nil
		@signal_timer = nil
		@start_time   = nil

		Thread.main[:signal_queue] = []
		@zmq_loop     = nil

		@api_handler = nil
		@event_publisher = nil
	end


	######
	public
	######

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


	#
	# :section: Startup/Shutdown
	#

	### Setup sockets and start the event loop.
	def run
		self.log.info "Getting ready to start the manager."
		self.setup_sockets
		self.set_signal_handlers
		self.start_accepting_requests

		return self # For chaining
	ensure
		self.restore_signal_handlers
		if @zmq_loop
			@zmq_loop.remove( @tree_sock )
			@tree_sock.pollable.close

			@zmq_loop.remove( @event_sock )
			@event_sock.pollable.close
		end
	end


	### Returns true if the Manager is running.
	def running?
		return @zmq_loop && @zmq_loop.running?
	end


	### Start a loop, accepting a request and handling it.
	def start_accepting_requests
		self.log.debug "Starting the main loop"

		@zmq_loop = ZMQ::Loop.new

		@api_handler = Arborist::Manager::TreeAPI.new( @tree_sock, self )
		@tree_sock.handler = @api_handler
		@zmq_loop.register( @tree_sock )

		@event_publisher = Arborist::Manager::EventPublisher.new( @event_sock, self, @zmq_loop )
		@event_sock.handler = @event_publisher
		@zmq_loop.register( @event_sock )

		self.setup_signal_timer
		self.start_time = Time.now

		self.log.debug "Manager running."
		@zmq_loop.start
	end


	### Create the ZMQ API socket if necessary.
	def setup_sockets
		self.log.debug "Setting up sockets"
		@tree_sock = self.setup_tree_socket
		@event_sock = self.setup_event_socket
	end


	### Set up the ZMQ REP socket for the Tree API.
	def setup_tree_socket
		sock = Arborist.zmq_context.socket( :REP )
		self.log.debug "  binding the tree API socket to %p" % [ Arborist.tree_api_url ]
		sock.linger = 0
		sock.bind( Arborist.tree_api_url )
		return ZMQ::Pollitem.new( sock, ZMQ::POLLIN )
	end


	### Set up the ZMQ PUB socket for published events.
	def setup_event_socket
		sock = Arborist.zmq_context.socket( :PUB )
		self.log.debug "  binding the event socket to %p" % [ Arborist.event_api_url ]
		sock.linger = 0
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
		@zmq_loop.stop if @zmq_loop
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
		@zmq_loop.register_timer( @signal_timer )
	end


	### Disable the timer that checks for incoming signals
	def cancel_signal_timer
		@signal_timer.cancel
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


	### Handle a USR1 signal. Writes a message to the log by default.
	def on_user1_signal( signo )
		self.log.info "Checkpoint: User signal."
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
		self.nodes.each do |identifier, node|
			next if node.operational?
			self.link_node_to_parent( node )
		end
		self.tree_built = true
	end


	### Link the specified +node+ to its parent. Raises an error if the specified +node+'s
	### parent is not yet loaded.
	def link_node_to_parent( node )
		parent_id = node.parent || '_'
		parent_node = self.nodes[ parent_id ] or
			raise "no parent '%s' node loaded for %p" % [ parent_id, node ]

		self.log.debug "adding %p as a child of %p" % [ node, parent_node ]
		parent_node.add_child( node )
	end


	### Add the specified +node+ to the Manager.
	def add_node( node )
		identifier = node.identifier

		unless self.nodes[identifier].equal?( node )
			self.remove_node( self.nodes[identifier] )
			self.nodes[ identifier ] = node
		end

		self.log.debug "Linking node %p to its parent" % [ node ]
		self.link_node_to_parent( node ) if self.tree_built?
	end


	### Remove a +node+ from the Manager. The +node+ can either be the Arborist::Node to
	### remove, or the identifier of a node.
	def remove_node( node )
		node = self.nodes[ node ] unless node.is_a?( Arborist::Node )
		return unless node

		raise "Can't remove an operational node" if node.operational?

		self.log.info "Removing node %p" % [ node ]
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
	def fetch_matching_node_states( filter, return_values, include_down=false )
		nodes_iter = if include_down
				self.all_nodes
			else
				self.reachable_nodes
			end

		states = nodes_iter.
			select {|node| node.matches?(filter) }.
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
		iter = self.enumerator_for( self.root ) do |node|
			!node.down?
		end
		return iter.each( &block ) if block
		return iter
	end


	### Return an enumerator for the specified +node+.
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



	#
	# Event API
	#

	### Create a subscription for the node with the specified +identifier+ and
	### +event_pattern+, using the given +criteria+ when considering an event.
	def create_subscription( identifier, event_pattern, criteria )
		identifier ||= '_'

		node = self.nodes[ identifier ] or raise ArgumentError, "no such node %p" % [ identifier ]
		sub = Arborist::Subscription.new( event_pattern, criteria )

		self.log.debug "Registering subscription %p" % [ sub ]
		node.add_subscription( sub )
		self.log.debug " adding '%s' to the subscriptions hash." % [ sub.id ]
		self.subscriptions[ sub.id ] = node
		self.log.debug "  subscriptions hash: %#0x" % [ self.subscriptions.object_id ]

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
		events.flatten!

		events.each do |event|
			subscriptions = node.find_matching_subscriptions( event )
			self.log.debug "Publishing to %d subscriptions" % [ subscriptions.length ]

			subscriptions.each do |sub|
				self.log.debug "  publishing a %s event to subscription %s" % [ event.type, sub.id ]
				self.publish_event( sub.id, event )
			end
		end

		if node.parent
			self.log.debug "Propagating events to the parent of %s: %s" %
				[ node.identifier, node.parent ]
			parent = self.nodes[ node.parent ]
			self.propagate_events( parent, *events )
		end
	end


	### Publish the specified +event+ on the event publication socket with the specified
	### subscription +identifier+.
	def publish_event( identifier, event )
		self.event_publisher.publish( identifier, event )
	end


	require 'arborist/manager/tree_api'
	require 'arborist/manager/event_publisher'

end # class Arborist::Manager
