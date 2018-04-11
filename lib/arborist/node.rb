# -*- ruby -*-
#encoding: utf-8

require 'set'
require 'uri'
require 'time'
require 'pathname'
require 'state_machines'

require 'loggability'
require 'pluggability'
require 'arborist' unless defined?( Arborist )
require 'arborist/mixins'
require 'arborist/exceptions'
require 'arborist/dependency'

using Arborist::TimeRefinements


# The basic node class for an Arborist tree
class Arborist::Node
	include Enumerable,
	        Arborist::HashUtilities
	extend Loggability,
	       Pluggability,
	       Arborist::MethodUtilities


	# The key for the thread local that is used to track instances as they're
	# loaded.
	LOADED_INSTANCE_KEY = :loaded_node_instances

	# Regex to match a valid identifier
	VALID_IDENTIFIER = /^\w[\w\-]*$/

	# The attributes of a node which are used in the operation of the system
	OPERATIONAL_ATTRIBUTES = %i[
		type
		status
		tags
		parent
		description
		dependencies
		status_changed
		last_contacted
		ack
		errors
		quieted_reasons
		config
	]

	# Node states that are unreachable by default.
	UNREACHABLE_STATES = %w[
		down
		disabled
		quieted
	]


	autoload :Root, 'arborist/node/root'
	autoload :Ack, 'arborist/node/ack'


	# Log via the Arborist logger
	log_to :arborist

	# Search for plugins in lib/arborist/node directories in loaded gems
	plugin_prefixes 'arborist/node'


	##
	# :method: unknown?
	# Returns +true+ if the node is in an 'unknown' state.

	##
	# :method: up?
	# Returns +true+ if the node is in an 'up' state.

	##
	# :method: down?
	# Returns +true+ if the node is in an 'down' state.

	##
	# :method: acked?
	# Returns +true+ if the node is in an 'acked' state.

	##
	# :method: disabled?
	# Returns +true+ if the node is in an 'disabled' state.

	##
	# :method: human_status_name
	# Return the node's status as a human-readable String.

	##
	# :method: status
	# Return the +status+ of the node. This will be one of: +unknown+, +up+, +down+, +acked+, or
	# +disabled+.

	##
	# :method: status=
	# :call-seq:
	#   status=( new_status )
	#
	# Set the status of the node to +new_status+.

	##
	# :method: status?
	# :call-seq:
	#   status?( status_name )
	#
	# Returns +true+ if the node's status is +status_name+.

	state_machine( :status, initial: :unknown ) do

		state :unknown,
			:up,
			:down,
			:warn,
			:acked,
			:disabled,
			:quieted

		event :update do
			transition [:down, :warn, :unknown, :acked] => :up, unless: :has_errors_or_warnings?
			transition [:up, :warn, :unknown] => :down, if: :has_errors?
			transition [:up, :unknown] => :warn, if: :has_only_warnings?
		end

		event :acknowledge do
			transition any - [:down, :acked] => :disabled
			transition [:down, :acked] => :acked
		end

		event :unacknowledge do
			transition [:acked, :disabled] => :warn, if: :has_warnings?
			transition [:acked, :disabled] => :down, if: :has_errors?
			transition [:acked, :disabled] => :unknown
		end

		event :handle_event do
			transition any - [:disabled, :quieted, :acked] => :quieted, if: :has_quieted_reason?
			transition :quieted => :unknown, unless: :has_quieted_reason?
		end

		event :reparent do
			transition any - [:disabled, :quieted, :acked] => :unknown
			transition :quieted => :unknown, unless: :has_quieted_reason?
		end

		after_transition any => :acked, do: :on_ack
		after_transition :acked => :up, do: :on_ack_cleared
		after_transition :down => :up, do: :on_node_up
		after_transition :up => :warn, do: :on_node_warn
		after_transition [:unknown, :warn, :up] => :down, do: :on_node_down
		after_transition [:unknown, :warn, :up] => :disabled, do: :on_node_disabled
		after_transition any => :quieted, do: :on_node_quieted
		after_transition :disabled => :unknown, do: :on_node_enabled
		after_transition :quieted => :unknown, do: :on_node_unquieted

		after_transition any => any, do: :log_transition
		after_transition any => any, do: :make_transition_event
		after_transition any => any, do: :update_status_changed

		after_transition do: :add_status_to_update_delta
	end


	### Return a curried Proc for the ::create method for the specified +type+.
	def self::curried_create( type )
		if type.subnode_type?
			return self.method( :create ).to_proc.curry( 3 )[ type ]
		else
			return self.method( :create ).to_proc.curry( 2 )[ type ]
		end
	end


	### Overridden to track instances of created nodes for the DSL.
	def self::new( * )
		new_instance = super
		Arborist::Node.add_loaded_instance( new_instance )
		return new_instance
	end


	### Create a new node with its state read from the specified +hash+.
	def self::from_hash( hash )
		return self.new( hash[:identifier] ) do
			self.marshal_load( hash )
		end
	end


	### Record a new loaded instance if the Thread-local variable is set up to track
	### them.
	def self::add_loaded_instance( new_instance )
		instances = Thread.current[ LOADED_INSTANCE_KEY ] or return
		# self.log.debug "Adding new instance %p to node tree" % [ new_instance ]
		instances << new_instance
	end


	### Inheritance hook -- add a DSL declarative function for the given +subclass+.
	def self::inherited( subclass )
		super

		body = self.curried_create( subclass )
		Arborist.add_dsl_constructor( subclass, &body )
	end


	### Get/set the node type instances of the class live under. If no parent_type is set, it
	### is a top-level node type. If a +block+ is given, it can be used to pre-process the
	### arguments into the (identifier, attributes, block) arguments used to create
	### the node instances.
	def self::parent_types( *types, &block )
		@parent_types ||= []

		types.each do |new_type|
			subclass = Arborist::Node.get_subclass( new_type )
			@parent_types << subclass
			subclass.add_subnode_factory_method( self, &block )
		end

		return @parent_types
	end
	singleton_method_alias :parent_type, :parent_types


	### Returns +true+ if the receiver must be created under a specific node type.
	def self::subnode_type?
		return ! self.parent_types.empty?
	end


	### Add a factory method that can be used to create subnodes of the specified +subnode_type+
	### on instances of the receiving class.
	def self::add_subnode_factory_method( subnode_type, &dsl_block )
		if subnode_type.name
			name = subnode_type.plugin_name
			# self.log.debug "Adding factory constructor for %s nodes to %p" % [ name, self ]
			body = lambda do |*args, &constructor_block|
				if dsl_block
					# self.log.debug "Using DSL block to split args: %p" % [ dsl_block ]
					identifier, attributes = dsl_block.call( *args )
				else
					# self.log.debug "Splitting args the default way: %p" % [ args ]
					identifier, attributes = *args
				end
				attributes ||= {}
				# self.log.debug "Identifier: %p, attributes: %p, self: %p" %
				# 	[ identifier, attributes, self ]

				return Arborist::Node.create( name, identifier, self, attributes, &constructor_block )
			end

			define_method( name, &body )
		else
			self.log.info "Skipping factory constructor for anonymous subnode class."
		end
	end


	### Load the specified +file+ and return any new Nodes created as a result.
	def self::load( file )
		self.log.info "Loading node file %s..." % [ file ]
		Thread.current[ LOADED_INSTANCE_KEY ] = []

		begin
			Kernel.load( file )
		rescue => err
			self.log.error "%p while loading %s: %s" % [ err.class, file, err.message ]
			raise
		end

		return Thread.current[ LOADED_INSTANCE_KEY ]
	ensure
		Thread.current[ LOADED_INSTANCE_KEY ] = nil
	end


	### Return an iterator for all the nodes supplied by the specified +loader+.
	def self::each_in( loader )
		return loader.nodes
	end


	### Create a new Node with the specified +identifier+, which must be unique to the
	### loaded tree.
	def initialize( identifier, *args, &block )
		attributes  = args.last.is_a?( Hash ) ? args.pop : {}
		parent_node = args.pop

		raise "Invalid identifier %p" % [identifier] unless
			identifier =~ VALID_IDENTIFIER

		# Attributes of the target
		@identifier      = identifier
		@parent          = parent_node ? parent_node.identifier : '_'
		@description     = nil
		@tags            = Set.new
		@properties      = {}
		@config          = {}
		@source          = nil
		@children        = {}
		@dependencies    = Arborist::Dependency.new( :all )

		# Primary state
		@status          = 'unknown'
		@status_changed  = Time.at( 0 )

		# Attributes that govern state
		@errors          = {}
		@warnings        = {}
		@ack             = nil
		@last_contacted  = Time.at( 0 )
		@quieted_reasons = {}

		# Event-handling
		@update_delta    = Hash.new do |h,k|
			h[ k ] = Hash.new( &h.default_proc )
		end
		@pending_change_events = []
		@subscriptions  = {}

		self.modify( attributes )
		self.instance_eval( &block ) if block
	end


	######
	public
	######

	##
	# The node's identifier
	attr_reader :identifier

	##
	# The URI of the source the object was read from
	attr_reader :source

	##
	# The Hash of nodes which are children of this node, keyed by identifier
	attr_reader :children

	##
	# Arbitrary attributes attached to this node via the manager API
	attr_reader :properties

	##
	# The Time the node was last contacted
	attr_accessor :last_contacted

	##
	# The Time the node's status last changed.
	attr_accessor :status_changed

	##
	# The Hash of last errors encountered by a monitor attempting to update this
	# node, keyed by the monitor's `key`.
	attr_accessor :errors

	##
	# The Hash of last warnings encountered by a monitor attempting to update this
	# node, keyed by the monitor's `key`.
	attr_accessor :warnings

	##
	# The acknowledgement currently in effect. Should be an instance of Arborist::Node::ACK
	attr_accessor :ack

	##
	# The Hash of changes tracked during an #update.
	attr_reader :update_delta

	##
	# The Array of events generated by the current update event
	attr_reader :pending_change_events

	##
	# The Hash of Subscription objects observing this node and its children, keyed by
	# subscription ID.
	attr_reader :subscriptions

	##
	# The node's secondary dependencies, expressed as an Arborist::Node::Sexp
	attr_accessor :dependencies

	##
	# The reasons this node was quieted. This is a Hash of text descriptions keyed by the
	# type of dependency it came from (either :primary or :secondary).
	attr_reader :quieted_reasons


	### Set the source of the node to +source+, which should be a valid URI.
	def source=( source )
		@source = URI( source )
	end


	### Set one or more node +attributes+. This should be overridden by subclasses which
	### wish to allow their operational attributes to be set/updated via the Tree API
	### (+modify+ and +graft+). Supported attributes are: +parent+, +description+, and
	### +tags+.
	def modify( attributes )
		attributes = stringify_keys( attributes )

		self.parent( attributes['parent'] )
		self.description( attributes['description'] )

		if attributes['tags']
			@tags.clear
			self.tags( attributes['tags'] )
		end
	end


	#
	# :section: DSLish declaration methods
	# These methods are both getter and setter for a node's attributes, used
	# in the node source.
	#

	### Get/set the node's parent node, which should either be an identifier or an object
	### that responds to #identifier with one.
	def parent( new_parent=nil )
		return @parent if new_parent.nil?

		@parent = if new_parent.respond_to?( :identifier )
				new_parent.identifier.to_s
			else
				@parent = new_parent.to_s
			end
	end


	### Get/set the node's description.
	def description( new_description=nil )
		return @description unless new_description
		@description = new_description.to_s
	end


	### Declare one or more +tags+ for this node.
	def tags( *tags )
		tags.flatten!
		@tags.merge( tags.map(&:to_s) ) unless tags.empty?
		return @tags.to_a
	end


	### Group +identifiers+ together in an 'any of' dependency.
	def any_of( *identifiers, on: nil )
		return Arborist::Dependency.on( :any, *identifiers, prefixes: on )
	end


	### Group +identifiers+ together in an 'all of' dependency.
	def all_of( *identifiers, on: nil )
		return Arborist::Dependency.on( :all, *identifiers, prefixes: on )
	end


	### Add secondary dependencies to the receiving node.
	def depends_on( *dependencies, on: nil )
		dependencies = self.all_of( *dependencies, on: on )

		self.log.debug "Setting secondary dependencies to: %p" % [ dependencies ]
		self.dependencies = check_dependencies( dependencies )
	end


	### Returns +true+ if the node has one or more secondary dependencies.
	def has_dependencies?
		return !self.dependencies.empty?
	end


	### Get or set the node's configuration hash. This can be used to pass per-node
	### information to systems using the tree (e.g., monitors, subscribers).
	def config( new_config=nil )
		@config.merge!( stringify_keys( new_config ) ) if new_config
		return @config
	end


	#
	# :section: Manager API
	# Methods used by the manager to manage its nodes.
	#


	### Return the simple type of this node (e.g., Arborist::Node::Host => 'host')
	def type
		return 'anonymous' unless self.class.name
		return self.class.name.sub( /.*::/, '' ).downcase
	end


	### Add the specified +subscription+ (an Arborist::Subscription) to the node.
	def add_subscription( subscription )
		self.subscriptions[ subscription.id ] = subscription
	end


	### Remove the specified +subscription+ (an Arborist::Subscription) from the node.
	def remove_subscription( subscription_id )
		return self.subscriptions.delete( subscription_id )
	end


	### Return subscriptions matching the specified +event+ on the receiving node.
	def find_matching_subscriptions( event )
		return self.subscriptions.values.find_all {|sub| event =~ sub }
	end


	### Return the Set of identifier of nodes that are secondary dependencies of this node.
	def node_subscribers
		self.log.debug "Finding node subscribers among %d subscriptions" % [ self.subscriptions.length ]
		return self.subscriptions.each_with_object( Set.new ) do |(identifier, sub), set|
			if sub.respond_to?( :node_identifier )
				set.add( sub.node_identifier )
			else
				self.log.debug "Skipping %p: not a node subscription" % [ sub ]
			end
		end
	end


	### Update specified +properties+ for the node.
	def update( new_properties )
		self.last_contacted = Time.now
		self.update_properties( new_properties )

		# Super to the state machine event method
		super

		events = self.pending_change_events.clone
		events << self.make_update_event
		events << self.make_delta_event unless self.update_delta.empty?

		results = self.broadcast_events( *events )
		self.log.debug ">>> Results from broadcast: %p" % [ results ]
		events.concat( results )

		return events
	ensure
		self.update_delta.clear
		self.pending_change_events.clear
	end


	### Update the node's properties with those in +new_properties+ (a String-keyed Hash)
	def update_properties( new_properties )
		new_properties = stringify_keys( new_properties )
		monitor_key = new_properties[ '_monitor_key' ] || '_'

		self.log.debug "Updated via a %s monitor: %p" % [ monitor_key, new_properties ]
		self.update_errors( monitor_key, new_properties.delete('error') )
		self.update_warnings( monitor_key, new_properties.delete('warning') )

		self.properties.merge!( new_properties, &self.method(:merge_and_record_delta) )
		compact_hash( self.properties )
	end


	### Update the errors hash for the specified +monitor_key+ to +value+.
	def update_errors( monitor_key, value=nil )
		if value
			self.errors[ monitor_key ] = value
		else
			self.errors.delete( monitor_key )
		end
	end


	### Update the warnings hash for the specified +monitor_key+ to +value+.
	def update_warnings( monitor_key, value=nil )
		if value
			self.warnings[ monitor_key ] = value
		else
			self.warnings.delete( monitor_key )
		end
	end


	### Acknowledge any current or future abnormal status for this node.
	def acknowledge( **args )
		self.ack = args

		super()

		events = self.pending_change_events.clone
		results = self.broadcast_events( *events )
		self.log.debug ">>> Results from broadcast: %p" % [ results ]
		events.concat( results )

		return events
	ensure
		self.pending_change_events.clear
	end


	### Clear any current acknowledgement.
	def unacknowledge
		self.ack = nil

		super()

		events = self.pending_change_events.clone
		results = self.broadcast_events( *events )
		self.log.debug ">>> Results from broadcast: %p" % [ results ]
		events.concat( results )

		return events
	ensure
		self.pending_change_events.clear
	end


	### Merge the specified +new_properties+ into the node's properties, recording
	### each change in the node's #update_delta.
	def merge_and_record_delta( key, oldval, newval, prefixes=[] )
		self.log.debug "Merging property %s: %p -> %p" % [
			(prefixes + [key]).join('.'),
			oldval,
			newval
		]

		# Merge them (recursively) if they're both merge-able
		if oldval.respond_to?( :merge! ) && newval.respond_to?( :merge! )
			return oldval.merge( newval ) do |ikey, ioldval, inewval|
				self.merge_and_record_delta( ikey, ioldval, inewval, prefixes + [key] )
			end

		# Otherwise just directly compare them and record any changes
		else
			unless oldval == newval
				prefixed_delta = prefixes.inject( self.update_delta ) do |hash, key|
					hash[ key ]
				end
				prefixed_delta[ key ] = [ oldval, newval ]
			end

			return newval
		end
	end


	### Return the node's state in an Arborist::Event of type 'node.update'.
	def make_update_event
		return Arborist::Event.create( 'node_update', self )
	end


	### Return an Event generated from the node's state changes.
	def make_delta_event
		self.log.debug "Making node.delta event: %p" % [ self.update_delta ]
		return Arborist::Event.create( 'node_delta', self, self.update_delta )
	end


	### Returns +true+ if the node's state has changed since the last time
	### #snapshot_state was called.
	def state_has_changed?
		return ! self.update_delta.empty?
	end


	### Returns +true+ if the specified search +criteria+ all match this node.
	def matches?( criteria, if_empty: true )

		# Omit 'delta' criteria from matches; delta matching is done separately.
		criteria = criteria.dup
		criteria.delete( 'delta' )

		self.log.debug "Node matching %p (%p if empty)" % [ criteria, if_empty ]
		return if_empty if criteria.empty?

		self.log.debug "Matching %p against criteria: %p" % [ self, criteria ]
		return criteria.all? do |key, val|
			self.match_criteria?( key, val )
		end.tap {|match| self.log.debug "  node %s match." % [ match ? "DID" : "did not"] }
	end


	### Returns +true+ if the node matches the specified +key+ and +val+ criteria.
	def match_criteria?( key, val )
		return case key
			when 'status'
				Array( val ).include?( self.status )
			when 'type'
				Array( val ).include?( self.type )
			when 'parent'
				self.parent == val
			when 'tag' then @tags.include?( val.to_s )
			when 'tags' then Array(val).all? {|tag| @tags.include?(tag) }
			when 'identifier'
				Array( val ).include?( self.identifier )
			when 'config'
				val.all? {|ikey, ival| hash_matches(@config, ikey, ival) }
			else
				hash_matches( @properties, key, val )
			end
	end


	### Return a Hash of node state values that match the specified +value_spec+.
	def fetch_values( value_spec=nil )
		state = self.properties.merge( self.operational_values )
		state = stringify_keys( state )
		state = make_serializable( state )

		if value_spec
			self.log.debug "Eliminating all values except: %p (from keys: %p)" %
				[ value_spec, state.keys ]
			state.delete_if {|key, _| !value_spec.include?(key) }
		end

		return state
	end


	### Return a Hash of the operational values that are included with the node's
	### monitor state.
	def operational_values
		values = OPERATIONAL_ATTRIBUTES.each_with_object( {} ) do |key, hash|
			hash[ key ] = self.send( key )
		end

		return values
	end


	### Register subscriptions for secondary dependencies on the receiving node with the
	### given +manager+.
	def register_secondary_dependencies( manager )
		self.dependencies.all_identifiers.each do |identifier|
			# Check to be sure the identifier isn't a descendant or ancestor
			if manager.ancestors_for( self ).any? {|node| node.identifier == identifier}
				raise Arborist::ConfigError, "Can't depend on ancestor node %p." % [ identifier ]
			elsif manager.descendants_for( self ).any? {|node| node.identifier == identifier }
				raise Arborist::ConfigError, "Can't depend on descendant node %p." % [ identifier ]
			end

			sub = Arborist::NodeSubscription.new( self )
			manager.subscribe( identifier, sub )
		end
	end


	### Publish the specified +events+ to any subscriptions the node has which match them.
	def publish_events( *events )
		self.log.debug "Got events to publish: %p" % [ events ]
		self.subscriptions.each_value do |sub|
			sub.on_events( *events )
		end
	end


	### Send an event to this node's immediate children.
	def broadcast_events( *events )
		events.flatten!
		results = self.children.flat_map do |identifier, child|
			self.log.debug "Broadcasting %d events to %p" % [ events.length, identifier ]
			events.flat_map do |event|
				child.handle_event( event )
			end
		end

		return results
	end


	### Handle the specified +event+, delivered either via broadcast or secondary
	### dependency subscription.
	def handle_event( event )
		self.log.debug "Handling %p" % [ event ]
		handler_name = "handle_%s_event" % [ event.type.gsub('.', '_') ]

		if self.respond_to?( handler_name )
			self.log.debug "Handling a %s event." % [ event.type ]
			self.method( handler_name ).call( event )
		else
			self.log.debug "No handler for a %s event!" % [ event.type ]
		end

		self.log.debug ">>> Pending change events before: %p" % [ self.pending_change_events ]

		super # to state-machine

		results = self.pending_change_events.clone
		self.log.debug ">>> Pending change events after: %p" % [ results ]
		results << self.make_delta_event unless self.update_delta.empty?

		child_results = self.broadcast_events( *results )
		results.concat( child_results )

		self.publish_events( *results )

		return results
	ensure
		self.update_delta.clear
		self.pending_change_events.clear
	end


	### Move a node from +old_parent+ to +new_parent+.
	def reparent( old_parent, new_parent )
		old_parent.remove_child( self )
		self.parent( new_parent.identifier )
		new_parent.add_child( self )

		self.quieted_reasons.delete( :primary )
		super
	end


	### Returns +true+ if this node's dependencies are not met.
	def dependencies_down?
		return self.dependencies.down?
	end
	alias_method :has_downed_dependencies?, :dependencies_down?


	### Returns +true+ if this node's dependencies are met.
	def dependencies_up?
		return !self.dependencies_down?
	end


	### Returns +true+ if any reasons have been set as to why the node has been
	### quieted. Guard condition for transition to and from `quieted` state.
	def has_quieted_reason?
		return !self.quieted_reasons.empty?
	end


	### Handle a 'node.down' event received via broadcast.
	def handle_node_down_event( event )
		self.log.debug "Got a node.down event: %p" % [ event ]
		self.dependencies.mark_down( event.node.identifier )

		if self.dependencies_down?
			self.quieted_reasons[ :secondary ] = "Secondary dependencies not met: %s" %
				[ self.dependencies.down_reason ]
		end

		if event.node.identifier == self.parent
			self.quieted_reasons[ :primary ] = "Parent down: %s" % [ self.parent ] # :TODO: backtrace?
		end
	end


	### Handle a 'node.disabled' event received via broadcast.
	def handle_node_disabled_event( event )
		self.log.debug "Got a node.disabled event: %p" % [ event ]
		self.dependencies.mark_down( event.node.identifier )

		if self.dependencies_down?
			self.quieted_reasons[ :secondary ] = "Secondary dependencies not met: %s" %
				[ self.dependencies.down_reason ]
		end

		if event.node.identifier == self.parent
			self.quieted_reasons[ :primary ] = "Parent disabled: %s" % [ self.parent ]
		end
	end


	### Handle a 'node.quieted' event received via broadcast.
	def handle_node_quieted_event( event )
		self.log.debug "Got a node.quieted event: %p" % [ event ]
		self.dependencies.mark_down( event.node.identifier )

		if self.dependencies_down?
			self.quieted_reasons[ :secondary ] = "Secondary dependencies not met: %s" %
				[ self.dependencies.down_reason ]
		end

		if event.node.identifier == self.parent
			self.quieted_reasons[ :primary ] = "Parent quieted: %s" % [ self.parent ] # :TODO: backtrace?
		end
	end


	### Handle a 'node.up' event received via broadcast.
	def handle_node_up_event( event )
		self.log.debug "Got a node.up event: %p" % [ event ]

		self.dependencies.mark_up( event.node.identifier )
		self.quieted_reasons.delete( :secondary ) if self.dependencies_up?

		if event.node.identifier == self.parent
			self.log.info "Parent of %s (%s) came back up." % [
				self.identifier,
				self.parent
			]
			self.quieted_reasons.delete( :primary )
		end
	end



	#
	# :section: Hierarchy API
	#

	### Enumerable API -- iterate over the children of this node.
	def each( &block )
		return self.children.values.each( &block )
	end


	### Returns +true+ if the node has one or more child nodes.
	def has_children?
		return !self.children.empty?
	end


	### Returns +true+ if the node is considered operational.
	def operational?
		return self.identifier.start_with?( '_' )
	end


	### Returns +true+ if the node's status indicates it shouldn't be
	### included by default when traversing nodes.
	def unreachable?
		self.log.debug "Testing for reachability; status is: %p" % [ self.status ]
		return UNREACHABLE_STATES.include?( self.status )
	end


	### Returns +true+ if the node's status indicates it is included by
	### default when traversing nodes.
	def reachable?
		return !self.unreachable?
	end


	### Register the specified +node+ as a child of this node, replacing any existing
	### node with the same identifier.
	def add_child( node )
		self.log.debug "Adding node %p as a child. Parent = %p" % [ node, node.parent ]
		raise "%p is not a child of %p" % [ node, self ] if
			node.parent && node.parent != self.identifier
		self.children[ node.identifier ] = node
	end


	### Append operator -- add the specified +node+ as a child and return +self+.
	def <<( node )
		self.add_child( node )
		return self
	end


	### Unregister the specified +node+ as a child of this node.
	def remove_child( node )
		self.log.debug "Removing node %p from children" % [ node ]
		return self.children.delete( node.identifier )
	end


	#
	# :section: Utility methods
	#


	### Return a description of the ack if it's set, or a generic string otherwise.
	def acked_description
		return self.ack.description if self.ack
		return "(unset)"
	end


	### Return a string describing the node's status.
	def status_description
		case self.status
		when 'up', 'down'
			return "%s as of %s" % [ self.status.upcase, self.last_contacted ]
		when 'acked'
			return "ACKed %s" % [ self.acked_description ]
		when 'disabled'
			return "disabled %s" % [ self.acked_description ]
		when 'quieted'
			reasons = self.quieted_reasons.values.join( ',' )
			return "quieted: %s" % [ reasons ]
		else
			return "in an unknown state"
		end
	end


	### Return a string describing node details; returns +nil+ for the base class. Subclasses
	### may override this to add to the output of #inspect.
	def node_description
		return nil
	end


	### Return a String representation of the object suitable for debugging.
	def inspect
		return "#<%p:%#x [%s] -> %s %p %s %s, %d children, %s>" % [
			self.class,
			self.object_id * 2,
			self.identifier,
			self.parent || 'root',
			self.description || "(no description)",
			self.node_description.to_s,
			self.source,
			self.children.length,
			self.status_description,
		]
	end


	#
	# :section: Serialization API
	#

	### Restore any saved state from the +old_node+ loaded from the state file. This is
	### used to overlay selective bits of the saved node tree to the equivalent nodes loaded
	### from node definitions.
	def restore( old_node )
		@status          = old_node.status
		@properties      = old_node.properties.dup
		@ack             = old_node.ack.dup if old_node.ack
		@last_contacted  = old_node.last_contacted
		@status_changed  = old_node.status_changed
		@errors          = old_node.errors
		@warnings        = old_node.warnings
		@quieted_reasons = old_node.quieted_reasons

		# Only merge in downed dependencies.
		old_node.dependencies.each_downed do |identifier, time|
			@dependencies.mark_down( identifier, time )
		end
	end


	### Return a Hash of the node's state. If +depth+ is greater than 0, that many
	### levels of child nodes are included in the node's `:children` value. Setting
	### +depth+ to a negative number will return all of the node's children.
	def to_h( depth: 0 )
		hash = {
			identifier: self.identifier,
			type: self.class.name.to_s.sub( /.+::/, '' ).downcase,
			parent: self.parent,
			description: self.description,
			tags: self.tags,
			config: self.config,
			status: self.status,
			properties: self.properties.dup,
			ack: self.ack ? self.ack.to_h : nil,
			last_contacted: self.last_contacted ? self.last_contacted.iso8601 : nil,
			status_changed: self.status_changed ? self.status_changed.iso8601 : nil,
			errors: self.errors,
			warnings: self.warnings,
			dependencies: self.dependencies.to_h,
			quieted_reasons: self.quieted_reasons,
		}

		if depth.nonzero?
			# self.log.debug "including children for depth %p" % [ depth ]
			hash[ :children ] = self.children.each_with_object( {} ) do |(ident, node), h|
				h[ ident ] = node.to_h( depth: depth - 1 )
			end
		else
			hash[ :children ] = {}
		end

		return hash
	end


	### Marshal API -- return the node as an object suitable for marshalling.
	def marshal_dump
		return self.to_h.merge( dependencies: self.dependencies )
	end


	### Marshal API -- set up the object's state using the +hash+ from a
	### previously-marshalled node.
	def marshal_load( hash )
		self.log.debug "Restoring from serialized hash: %p" % [ hash ]
		@identifier      = hash[:identifier]
		@properties      = hash[:properties]

		@parent          = hash[:parent]
		@description     = hash[:description]
		@tags            = Set.new( hash[:tags] )
		@config          = hash[:config]
		@children        = {}

		@status          = hash[:status]
		@status_changed  = Time.parse( hash[:status_changed] )
		@ack             = Arborist::Node::Ack.from_hash( hash[:ack] ) if hash[:ack]

		@errors          = hash[:errors]
		@warnings        = hash[:warnings]
		@properties      = hash[:properties] || {}
		@last_contacted  = Time.parse( hash[:last_contacted] )
		@quieted_reasons = hash[:quieted_reasons] || {}
		self.log.debug "Deps are: %p" % [ hash[:dependencies] ]
		@dependencies    = hash[:dependencies]

		@update_delta    = Hash.new do |h,k|
			h[ k ] = Hash.new( &h.default_proc )
		end

		@pending_change_events = []
		@subscriptions         = {}

	end


	### Equality operator -- returns +true+ if +other_node+ has the same identifier, parent, and
	### state as the receiving one.
	def ==( other_node )
		return \
			other_node.identifier == self.identifier &&
			other_node.parent == self.parent &&
			other_node.description == self.description &&
			other_node.tags == self.tags
	end


	#########
	protected
	#########

	### Ack the node with the specified +ack_data+, which should contain
	def ack=( ack_data )
		if ack_data
			self.log.info "Node %s ACKed with data: %p" % [ self.identifier, ack_data ]
			@ack = Arborist::Node::Ack.from_hash( ack_data )
		else
			self.log.info "Node %s ACK cleared explicitly" % [ self.identifier ]
			@ack = nil
		end
	end


	### State machine guard predicate -- Returns +true+ if the node has an ACK status set.
	def ack_set?
		self.log.debug "Checking to see if this node has been ACKed (it %s)" %
			[ @ack ? "has" : "has not" ]
		return @ack ? true : false
	end


	### State machine guard predicate -- returns +true+ if the node has errors.
	def has_errors?
		has_errors = ! self.errors.empty?
		self.log.debug "Checking to see if last contact cleared remaining errors (it %s)" %
			[ has_errors ? "did not" : "did" ]
		self.log.debug "Errors are: %p" % [ self.errors ]
		return has_errors
	end


	### State machine guard predicate -- Returns +true+ if the node has errors
	### and does not have an ACK status set.
	def has_unacked_errors?
		return self.has_errors? && !self.ack_set?
	end


	### State machine guard predicate -- returns +true+ if the node has warnings.
	def has_warnings?
		has_warnings = ! self.warnings.empty?
		self.log.debug "Checking to see if last contact cleared remaining warnings (it %s)" %
			[ has_warnings ? "did not" : "did" ]
		self.log.debug "Warnings are: %p" % [ self.warnings ]
		return has_warnings
	end


	### State machine guard predicate -- returns +true+ if the node has warnings or errors.
	def has_errors_or_warnings?
		return self.has_errors? || self.has_warnings?
	end


	### State machine guard predicate -- returns +true+ if the node has warnings but
	### no errors.
	def has_only_warnings?
		return self.has_warnings? && ! self.has_errors?
	end


	### Return a string describing the errors that are set on the node.
	def errors_description
		return "No errors" if self.errors.empty?
		return self.errors.map do |key, msg|
			"%s: %s" % [ key, msg ]
		end.join( '; ' )
	end


	### Return a string describing the warnings that are set on the node.
	def warnings_description
		return "No warnings" if self.warnings.empty?
		return self.warnings.map do |key, msg|
			"%s: %s" % [ key, msg ]
		end.join( '; ' )
	end


	#
	# :section: State Callbacks
	#

	### Log every status transition
	def log_transition( transition )
		self.log.debug "Transitioned %s from %s to %s" %
			[ self.identifier, transition.from, transition.to ]
	end


	### Update the last status change time.
	def update_status_changed( transition )
		self.status_changed = Time.now
	end


	### Queue up a transition event whenever one happens
	def make_transition_event( transition )
		node_type = "node_%s" % [ transition.to ]
		self.log.debug "Making a %s event for %p" % [ node_type, transition ]
		self.pending_change_events << Arborist::Event.create( node_type, self )
	end


	### Callback for when an acknowledgement is set.
	def on_ack( transition )
		self.log.warn "ACKed: %s" % [ self.status_description ]
	end


	### Callback for when an acknowledgement is cleared.
	def on_ack_cleared( transition )
		self.log.warn "ACK cleared for %s" % [ self.identifier ]
		self.ack = nil
	end


	### Callback for when a node goes from down to up
	def on_node_up( transition )
		self.errors.clear
		self.log.warn "%s is %s" % [ self.identifier, self.status_description ]
	end


	### Callback for when a node goes from up to down
	def on_node_down( transition )
		self.log.error "%s is %s" % [ self.identifier, self.status_description ]
		self.update_delta[ 'errors' ] = [ nil, self.errors_description ]
	end


	### Callback for when a node goes from up to warn
	def on_node_warn( transition )
		self.log.error "%s is %s" % [ self.identifier, self.status_description ]
		self.update_delta[ 'warnings' ] = [ nil, self.warnings_description ]
	end


	### Callback for when a node goes from up to disabled
	def on_node_disabled( transition )
		self.log.warn "%s is %s" % [ self.identifier, self.status_description ]
	end


	### Callback for when a node goes from any state to quieted
	def on_node_quieted( transition )
		self.log.warn "%s is %s" % [ self.identifier, self.status_description ]
	end


	### Callback for when a node transitions from quieted to unknown
	def on_node_unquieted( transition )
		self.log.warn "%s is %s" % [ self.identifier, self.status_description ]
	end


	### Callback for when a node goes from disabled to unknown
	def on_node_enabled( transition )
		self.log.warn "%s is %s" % [ self.identifier, self.status_description ]
	end


	### Add the transition from one state to another to the data used to build
	### deltas for the #update event.
	def add_status_to_update_delta( transition )
		self.update_delta[ 'status' ] = [ transition.from, transition.to ]
	end


	#######
	private
	#######

	### Check the specified +dependencies+ (an Arborist::Dependency) for illegal dependencies
	### and raise an error if any are found.
	def check_dependencies( dependencies )
		identifiers = dependencies.all_identifiers

		self.log.debug "Checking dependency identifiers: %p" % [ identifiers ]
		if identifiers.include?( '_' )
			raise Arborist::ConfigError, "a node can't depend on the root node"
		elsif identifiers.include?( self.identifier )
			raise Arborist::ConfigError, "a node can't depend on itself"
		end

		return dependencies
	end


	### Turn any non-msgpack-able objects in the values of a copy of +hash+ to
	### values that can be serialized and return the copy.
	def make_serializable( hash )
		new_hash = hash.dup
		new_hash.keys.each do |key|
			val = new_hash[ key ]
			case val
			when Hash
				new_hash[ key ] = make_serializable( val )

			when Arborist::Dependency,
			     Arborist::Node::Ack
				 new_hash[ key ] = val.to_h

			when Time
				new_hash[ key ] = val.iso8601
			end
		end

		return new_hash
	end

end # class Arborist::Node
