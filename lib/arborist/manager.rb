# -*- ruby -*-
#encoding: utf-8

require 'securerandom'
require 'pathname'
require 'tempfile'
require 'configurability'
require 'loggability'
require 'cztop'
require 'cztop/reactor'
require 'cztop/reactor/signal_handling'

require 'arborist' unless defined?( Arborist )
require 'arborist/node'
require 'arborist/mixins'
require 'arborist/tree_api'
require 'arborist/event_api'


# The main Arborist process -- responsible for coordinating all other activity.
class Arborist::Manager
	extend Configurability,
		   Loggability,
	       Arborist::MethodUtilities
	include CZTop::Reactor::SignalHandling


	# Signals the manager responds to
	QUEUE_SIGS = [
		:INT, :TERM, :HUP, :USR1,
		# :TODO: :QUIT, :WINCH, :USR2, :TTIN, :TTOU
	] & Signal.list.keys.map( &:to_sym )

	# Array of actions supported by the Tree API
	VALID_TREEAPI_ACTIONS = %w[
		deps
		fetch
		graft
		modify
		prune
		search
		status
		subscribe
		unsubscribe
		update
	]


	# Use the Arborist logger
	log_to :arborist

	# Configurability API -- use the 'arborist' section
	configurability( 'arborist.manager' ) do

		##
		# The Pathname of the file the manager's node tree state is saved to
		setting :state_file, default: nil do |value|
			value && Pathname( value )
		end

		##
		# The number of seconds between automatic state checkpoints
		setting :checkpoint_frequency, default: 30.0 do |value|
			if value
				value = value.to_f
				value = nil unless value > 0
			end
			value
		end

		##
		# The number of seconds between heartbeat events
		setting :heartbeat_frequency, default: 1.0 do |value|
			raise Arborist::ConfigError, "heartbeat must be positive and non-zero" if
				!value || value <= 0
			Float( value )
		end

		##
		# The maximum amount of time to wait for pending events to be delivered during
		# shutdown, in seconds.
		setting :linger, default: 5.0 do |value|
			value && value.to_f
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

		@start_time   = nil

		@checkpoint_timer = nil
		@linger = self.class.linger
		self.log.info "Linger set to %p" % [ @linger ]

		@reactor = CZTop::Reactor.new
		@tree_socket = nil
		@event_socket = nil
		@event_queue = []

		@heartbeat_timer = nil
		@checkpoint_timer = nil
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
	# The CZTop::Reactor that runs the event loop
	attr_reader :reactor

	##
	# The ZeroMQ socket REP socket that handles Tree API requests
	attr_accessor :tree_socket

	##
	# The ZeroMQ PUB socket that publishes events for the Event API
	attr_accessor :event_socket

	##
	# The queue of pending Event API events
	attr_reader :event_queue

	##
	# Flag for marking when the tree is built successfully the first time
	attr_predicate_accessor :tree_built

	##
	# The maximum amount of time to wait for pending events to be delivered during
	# shutdown, in milliseconds.
	attr_reader :linger

	##
	# The Timers::Timer that periodically checkpoints the manager's state (if it's
	# configured to do so)
	attr_reader :checkpoint_timer

	##
	# The Timers::Timer that periodically publishes a heartbeat event
	attr_reader :heartbeat_timer


	#
	# :section: Startup/Shutdown
	#

	### Setup sockets and start the event loop.
	def run
		self.log.info "Getting ready to start the manager."
		self.setup_sockets
		self.register_timers
		self.with_signal_handler( reactor, *QUEUE_SIGS ) do
			self.start_accepting_requests
		end
	ensure
		self.shutdown_sockets
		self.save_node_states
	end


	### Create the sockets used by the manager and bind them to the appropriate
	### endpoints.
	def setup_sockets
		self.setup_tree_socket
		self.setup_event_socket
	end


	### Shut down the sockets used by the manager.
	def shutdown_sockets
		self.shutdown_tree_socket
		self.shutdown_event_socket
	end


	### Returns true if the Manager is running.
	def running?
		return self.reactor &&
			self.event_socket &&
			self.reactor.registered?( self.event_socket )
	end


	### Register the Manager's timers.
	def register_timers
		self.register_checkpoint_timer
		self.register_heartbeat_timer
	end


	### Register the Manager's timers.
	def cancel_timers
		self.cancel_heartbeat_timer
		self.cancel_checkpoint_timer
	end


	### Start a loop, accepting a request and handling it.
	def start_accepting_requests
		self.log.debug "Starting the main loop"

		self.start_time = Time.now

		self.reactor.register( self.tree_socket, :read, &self.method(:on_tree_socket_event) )
		self.reactor.register( self.event_socket, :write, &self.method(:on_event_socket_event) )

		self.log.debug "Manager running."
		return self.reactor.start_polling( ignore_interrupts: true )
	end


	### Restart the manager
	def restart
		raise NotImplementedError
	end


	### Stop the manager.
	def stop
		self.log.info "Stopping the manager."
		self.reactor.stop_polling
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


	### Register a periodic timer that will publish a heartbeat event at a
	### configurable interval.
	def register_heartbeat_timer
		interval = self.class.heartbeat_frequency

		self.log.info "Setting up to heartbeat every %ds" % [ interval ]
		@heartbeat_timer = self.reactor.add_periodic_timer( interval ) do
			self.publish_heartbeat_event
		end
	end


	### Cancel the timer that publishes heartbeat events.
	def cancel_heartbeat_timer
		self.reactor.remove_timer( self.heartbeat_timer )
	end


	### Resume the timer that publishes heartbeat events.
	def resume_heartbeat_timer
		self.reactor.resume_timer( self.heartbeat_timer )
	end


	### Register a periodic timer that will save a snapshot of the node tree's state to the state
	### file on a configured interval if one is configured.
	def register_checkpoint_timer
		unless self.class.state_file
			self.log.info "No state file configured; skipping checkpoint timer setup."
			return nil
		end
		interval = self.class.checkpoint_frequency
		unless interval && interval.nonzero?
			self.log.info "Checkpoint frequency is %p; skipping checkpoint timer setup." % [ interval ]
			return nil
		end

		self.log.info "Setting up node state checkpoint every %0.3fs" % [ interval ]
		@checkpoint_timer = self.reactor.add_periodic_timer( interval ) do
			self.save_node_states
		end
	end


	### Cancel the timer that saves tree snapshots.
	def cancel_checkpoint_timer
		self.reactor.remove_timer( self.checkpoint_timer )
	end


	### Resume the timer that saves tree snapshots.
	def resume_checkpoint_timer
		self.reactor.resume_timer( self.checkpoint_timer )
	end


	#
	# :section: Signal Handling
	# These methods set up some behavior for starting, restarting, and stopping
	# the manager when a signal is received.
	#

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


	### Traverse the node tree and return the specified +return_values+ from any nodes which
	### match the given +filter+, skipping downed nodes and all their children
	### unless +include_down+ is set. If +return_values+ is set to +nil+, then all
	### values from the node will be returned.
	def find_matching_node_states( filter, return_values, include_down=false, negative_filter={} )
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
	# Tree network API
	#


	### Set up the ZeroMQ REP socket for the Tree API.
	def setup_tree_socket
		@tree_socket = CZTop::Socket::REP.new
		self.log.info "  binding the tree API socket (%#0x) to %p" %
			[ @tree_socket.object_id * 2, Arborist.tree_api_url ]
		@tree_socket.options.linger = 0
		@tree_socket.bind( Arborist.tree_api_url )
	end


	### Tear down the ZeroMQ REP socket.
	def shutdown_tree_socket
		@tree_socket.unbind( @tree_socket.last_endpoint )
		@tree_socket = nil
	end


	### ZMQ::Handler API -- Read and handle an incoming request.
	def on_tree_socket_event( event )
		if event.readable?
			request = event.socket.receive
			msg = self.dispatch_request( request )
			event.socket << msg
		else
			raise "Unsupported event %p on tree API socket!" % [ event ]
		end
	end


	### Handle the specified +raw_request+ and return a response.
	def dispatch_request( raw_request )
		raise "Manager is shutting down" unless self.running?

		header, body = Arborist::TreeAPI.decode( raw_request )
		handler = self.lookup_tree_request_action( header )

		return handler.call( header, body )

	rescue => err
		self.log.error "%p: %s" % [ err.class, err.message ]
		err.backtrace.each {|frame| self.log.debug "  #{frame}" }

		errtype = case err
			when Arborist::MessageError,
			     Arborist::ConfigError,
			     Arborist::NodeError
				'client'
			else
				'server'
			end

		return Arborist::TreeAPI.error_response( errtype, err.message )
	end


	### Given a request +header+, return a #call-able object that can handle the response.
	def lookup_tree_request_action( header )
		raise Arborist::MessageError, "unsupported version %d" % [ header['version'] ] unless
			header['version'] == 1

		action = header['action'] or
			raise Arborist::MessageError, "missing required header 'action'"
		raise Arborist::MessageError, "No such action '%s'" % [ action ] unless
			VALID_TREEAPI_ACTIONS.include?( action )

		handler_name = "handle_%s_request" % [ action ]
		return self.method( handler_name )
	end


	### Return a response to the `status` action.
	def handle_status_request( header, body )
		self.log.info "STATUS: %p" % [ header ]
		return Arborist::TreeAPI.successful_response(
			server_version: Arborist::VERSION,
			state: self.running? ? 'running' : 'not running',
			uptime: self.uptime,
			nodecount: self.nodecount
		)
	end


	### Return a response to the `subscribe` action.
	def handle_subscribe_request( header, body )
		self.log.info "SUBSCRIBE: %p" % [ header ]
		event_type      = header[ 'event_type' ]
		node_identifier = header[ 'identifier' ]

		body = [ body ] unless body.is_a?( Array )
		positive = body.shift
		negative = body.shift || {}

		subscription = self.create_subscription( node_identifier, event_type, positive, negative )
		self.log.info "Subscription to %s events at or under %s: %p" %
			[ event_type || 'all', node_identifier || 'the root node', subscription ]

		return Arborist::TreeAPI.successful_response( id: subscription.id )
	end


	### Return a response to the `unsubscribe` action.
	def handle_unsubscribe_request( header, body )
		self.log.info "UNSUBSCRIBE: %p" % [ header ]
		subscription_id = header[ 'subscription_id' ] or
			return Arborist::TreeAPI.error_response( 'client', 'No identifier specified for UNSUBSCRIBE.' )
		subscription = self.remove_subscription( subscription_id ) or
			return Arborist::TreeAPI.successful_response( nil )

		self.log.info "Destroyed subscription: %p" % [ subscription ]
		return Arborist::TreeAPI.successful_response(
			event_type: subscription.event_type,
			criteria: subscription.criteria
		)
	end


	### Return a repsonse to the `fetch` action.
	def handle_fetch_request( header, body )
		self.log.info "FETCH: %p" % [ header ]
		from  = header['from'] || '_'
		depth = header['depth']
		tree  = header['tree']

		start_node = self.nodes[ from ] or
			return Arborist::TreeAPI.error_response( 'client', "No such node %s." % [from] )
		self.log.debug "  Listing nodes under %p" % [ start_node ]

		if tree
			iter = [ start_node.to_h(depth: (depth || -1)) ]
		elsif depth
			self.log.debug "    depth limited to %d" % [ depth ]
			iter = self.depth_limited_enumerator_for( start_node, depth )
		else
			self.log.debug "    no depth limit"
			iter = self.enumerator_for( start_node )
		end
		data = iter.map( &:to_h )
		self.log.debug "  got data for %d nodes" % [ data.length ]

		return Arborist::TreeAPI.successful_response( data )
	end


	### Return a response to the `deps` action.
	def handle_deps_request( header, body )
		self.log.info "DEPS: %p" % [ header ]
		from = header['from'] || '_'

		start_node = self.nodes[ from ] or
			return Arborist::TreeAPI.error_response( 'client', "No such node %s." % [from] )
		iter = self.enumerator_for( start_node )
		deps = iter.inject( Set.new ) do |depset, node|
			nsubs = node.node_subscribers
			self.log.debug "Merging %d node subscribers from %s" % [ nsubs.length, node.identifier ]
			depset | nsubs
		end

		return Arborist::TreeAPI.successful_response({ deps: deps.to_a })
	end


	### Return a response to the 'search' action.
	def handle_search_request( header, body )
		self.log.info "SEARCH: %p" % [ header ]

		include_down = header['include_down']
		values = if header.key?( 'return' )
				header['return'] || []
			else
				nil
			end

		body = [ body ] unless body.is_a?( Array )
		positive = body.shift
		negative = body.shift || {}
		states = self.find_matching_node_states( positive, values, include_down, negative )

		return Arborist::TreeAPI.successful_response( states )
	end


	### Update nodes using the data from the update request's +body+.
	def handle_update_request( header, body )
		self.log.info "UPDATE: %p" % [ header ]

		unless body.respond_to?( :each )
			return Arborist::TreeAPI.error_response( 'client', 'Malformed update: body does not respond to #each' )
		end

		body.each do |identifier, properties|
			self.update_node( identifier, properties )
		end

		return Arborist::TreeAPI.successful_response( nil )
	end


	### Remove a node and its children.
	def handle_prune_request( header, body )
		self.log.info "PRUNE: %p" % [ header ]

		identifier = header[ 'identifier' ] or
			return Arborist::TreeAPI.error_response( 'client', 'No identifier specified for PRUNE.' )
		node = self.remove_node( identifier )

		return Arborist::TreeAPI.successful_response( node ? node.to_h : nil )
	end


	### Add a node
	def handle_graft_request( header, body )
		self.log.info "GRAFT: %p" % [ header ]

		identifier = header[ 'identifier' ] or
			return Arborist::TreeAPI.error_response( 'client', 'No identifier specified for GRAFT.' )

		if self.nodes[ identifier ]
			return Arborist::TreeAPI.error_response( 'client', "Node %p already exists." % [identifier] )
		end

		type = header[ 'type' ] or
			return Arborist::TreeAPI.error_response( 'client', 'No type specified for GRAFT.' )
		parent = header[ 'parent' ] || '_'
		parent_node = self.nodes[ parent ] or
			return Arborist::TreeAPI.error_response( 'client', 'No parent node found for %s.' % [parent] )

		self.log.debug "Grafting a new %s node under %p" % [ type, parent_node ]

		# If the parent has a factory method for the node type, use it, otherwise
		# use the Pluggability factory
		node = if parent_node.respond_to?( type )
				parent_node.method( type ).call( identifier, body )
			else
				body.merge!( parent: parent )
				Arborist::Node.create( type, identifier, body )
			end

		self.add_node( node )

		return Arborist::TreeAPI.successful_response( node ? {identifier: node.identifier} : nil )
	end


	### Modify a node's operational attributes
	def handle_modify_request( header, body )
		self.log.info "MODIFY: %p" % [ header ]

		identifier = header[ 'identifier' ] or
			return Arborist::TreeAPI.error_response( 'client', 'No identifier specified for MODIFY.' )
		return Arborist::TreeAPI.error_response( 'client', "Unable to MODIFY root node." ) if identifier == '_'
		node = self.nodes[ identifier ] or
			return Arborist::TreeAPI.error_response( 'client', "No such node %p" % [identifier] )

		self.log.debug "Modifying operational attributes of the %s node: %p" % [ identifier, body ]

		if new_parent_identifier = body.delete( 'parent' )
			old_parent = self.nodes[ node.parent ]
			new_parent = self.nodes[ new_parent_identifier ] or
				return Arborist::TreeAPI.error_response( 'client', "No such parent node: %p" % [new_parent_identifier] )
			node.reparent( old_parent, new_parent )
		end

		node.modify( body )

		return Arborist::TreeAPI.successful_response( nil )
	end


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

	### Set up the ZMQ PUB socket for published events.
	def setup_event_socket
		@event_socket = CZTop::Socket::PUB.new
		self.log.info "  binding the event socket (%#0x) to %p" %
			[ @event_socket.object_id * 2, Arborist.event_api_url ]
		@event_socket.options.linger = ( self.linger * 1000 ).ceil
		@event_socket.bind( Arborist.event_api_url )
	end


	### Stop accepting events to be published
	def shutdown_event_socket
		start   = Time.now
		timeout = start + (self.linger.to_f / 2.0)

		self.log.warn "Waiting to empty the event queue..."
		until self.event_queue.empty?
			sleep 0.1
			break if Time.now > timeout
		end
		self.log.warn "  ... waited %0.1f seconds" % [ Time.now - start ]

		@event_socket.options.linger = 0
		@event_socket.unbind( @event_socket.last_endpoint )
		@event_socket = nil
	end


	### Publish the specified +event+.
	def publish( identifier, event )
		self.event_queue << Arborist::EventAPI.encode( identifier, event.to_h )
		self.register_event_socket if self.running?
	end


	### Register the publisher with the reactor if it's not already.
	def register_event_socket
		self.log.debug "Registering event socket for write events."
		self.reactor.enable_events( self.event_socket, :write ) unless
			self.reactor.event_enabled?( self.event_socket, :write )
	end


	### Unregister the event publisher socket from the reactor if it's registered.
	def unregister_event_socket
		self.log.debug "Unregistering event socket for write events."
		self.reactor.disable_events( self.event_socket, :write ) if
			self.reactor.event_enabled?( self.event_socket, :write )
	end


	### IO event handler for the event socket.
	def on_event_socket_event( event )
		if event.writable?
			if (( msg = self.event_queue.shift ))
				# self.log.debug "Publishing event %p" % [ msg ]
				event.socket << msg
			end
		else
			raise "Unhandled event %p on the event socket" % [ event ]
		end

		self.unregister_event_socket if self.event_queue.empty?
	end


	### Publish a system event that observers can watch for to detect restarts.
	def publish_heartbeat_event
		return unless self.start_time
		self.publish_system_event( 'heartbeat',
			run_id: self.run_id,
			start_time: self.start_time.iso8601,
			version: Arborist::VERSION
		)
	end


	### Publish an event with the specified +eventname+ and +data+.
	def publish_system_event( eventname, **data )
		eventname = eventname.to_s
		eventname = 'sys.' + eventname unless eventname.start_with?( 'sys.' )
		self.log.debug "Publishing %s event: %p." % [ eventname, data ]
		self.publish( eventname, data )
	end


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


	### Create a subscription that publishes to the Manager's event publisher for
	### the node with the specified +identifier+ and +event_pattern+, using the
	### given +criteria+ when considering an event.
	def create_subscription( identifier, event_pattern, criteria, negative_criteria={} )
		sub = Arborist::Subscription.new( event_pattern, criteria, negative_criteria ) do |*args|
			self.publish( *args )
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


end # class Arborist::Manager
