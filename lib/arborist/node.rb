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

using Arborist::TimeRefinements


# The basic node class for an Arborist tree
class Arborist::Node
	include Enumerable,
	        Arborist::HashUtilities
	extend Loggability,
	       Pluggability,
	       Arborist::MethodUtilities


	##
	# The key for the thread local that is used to track instances as they're
	# loaded.
	LOADED_INSTANCE_KEY = :loaded_node_instances


	##
	# The struct for the 'ack' operational property
	ACK = Struct.new( 'ArboristNodeACK', :message, :via, :sender, :time )

	##
	# The keys required to be set for an ACK
	ACK_REQUIRED_PROPERTIES = %w[ message sender ]


	##
	# Log via the Arborist logger
	log_to :arborist

	##
	# Search for plugins in lib/arborist/node directories in loaded gems
	plugin_prefixes 'arborist/node'


	state_machine( :status, initial: :unknown ) do

		state :unknown,
			:up,
			:down,
			:acked,
			:disabled

		event :update do
			transition [:down, :unknown, :acked] => :up, if: :last_contact_successful?
			transition [:up, :unknown] => :down, unless: :last_contact_successful?
			transition :down => :acked, if: :ack_set?
			transition [:unknown, :up] => :disabled, if: :ack_set?
			transition :disabled => :unknown, unless: :ack_set?
		end

		after_transition any => :acked, do: :on_ack
		after_transition :acked => :up, do: :on_ack_cleared
		after_transition :down => :up, do: :on_node_up
		after_transition [:unknown, :up] => :down, do: :on_node_down
		after_transition [:unknown, :up] => :disabled, do: :on_node_disabled
		after_transition :disabled => :unknown, do: :on_node_enabled

		after_transition any => any, do: :log_transition

		after_transition do: :add_status_to_update_delta
	end


	### Return a curried Proc for the ::create method for the specified +type+.
	def self::curried_create( type )
		return self.method( :create ).to_proc.curry( 2 )[ type ]
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
		instances << new_instance
	end


	### Inheritance hook -- add a DSL declarative function for the given +subclass+.
	def self::inherited( subclass )
		super

		if name = subclass.name
			name.sub!( /.*::/, '' )
			body = self.curried_create( subclass )
			Arborist.add_dsl_constructor( name, &body )
		else
			self.log.info "Skipping DSL constructor for anonymous class."
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
	def initialize( identifier, &block )
		raise "Invalid identifier %p" % [identifier] unless
			identifier =~ /^\w[\w\-]*$/

		@identifier     = identifier
		@parent         = '_'
		@description    = nil
		@tags           = Set.new
		@source         = nil
		@children       = {}

		@status         = 'unknown'
		@status_changed = Time.at( 0 )

		@error          = nil
		@ack            = nil
		@properties     = {}
		@last_contacted = Time.at( 0 )

		@update_delta   = Hash.new do |h,k|
			h[ k ] = Hash.new( &h.default_proc )
		end
		@pending_update_events = []
		@subscriptions  = {}

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
	# The last error encountered by a monitor attempting to update this node.
	attr_accessor :error

	##
	# The acknowledgement currently in effect. Should be an instance of Arborist::Node::ACK
	attr_accessor :ack

	##
	# The Hash of changes tracked during an #update.
	attr_reader :update_delta

	##
	# The Array of events generated by the current update event
	attr_reader :pending_update_events

	##
	# The Hash of Subscription objects observing this node and its children, keyed by
	# subscription ID.
	attr_reader :subscriptions


	### Set the source of the node to +source+, which should be a valid URI.
	def source=( source )
		@source = URI( source )
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
		@tags.merge( tags.map(&:to_s) ) unless tags.empty?
		return @tags.to_a
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


	### Publish the specified +events+ to any subscriptions the node has which match them.
	def publish_events( *events )
		self.subscriptions.each_value do |sub|
			sub.on_events( *events )
		end
	end


	### Update specified +properties+ for the node.
	def update( new_properties )
		new_properties = stringify_keys( new_properties )
		self.log.debug "Updated: %p" % [ new_properties ]

		self.last_contacted = Time.now
		if new_properties.key?( 'ack' )
			self.ack = new_properties.delete( 'ack' )
		else
			self.error = new_properties.delete( 'error' )
		end

		self.properties.merge!( new_properties, &self.method(:merge_and_record_delta) )
		compact_hash( self.properties )

		# Super to the state machine event method
		super

		events = self.pending_update_events.clone
		events << self.make_update_event
		events << self.make_delta_event unless self.update_delta.empty?

		return events
	ensure
		self.update_delta.clear
		self.pending_update_events.clear
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
	def matches?( criteria )
		self.log.debug "Matching %p against criteria: %p" % [ self, criteria ]
		return criteria.all? do |key, val|
			self.match_criteria?( key, val )
		end.tap {|match| self.log.debug "  node %s match." % [ match ? "DID" : "did not"] }
	end


	### Returns +true+ if the node matches the specified +key+ and +val+ criteria.
	def match_criteria?( key, val )
		return case key
			when 'status'
				self.status == val
			when 'type'
				self.log.debug "Checking node type %p against %p" % [ self.type, val ]
				self.type == val
			when 'tag' then @tags.include?( val.to_s )
			when 'tags' then Array(val).all? {|tag| @tags.include?(tag) }
			when 'identifier' then @identifier == val
			else
				hash_matches( @properties, key, val )
			end
	end


	### Return a Hash of node state values that match the specified +value_spec+.
	def fetch_values( value_spec=nil )
		state = self.properties.merge( self.operational_values )
		state = stringify_keys( state )

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
		values = {
			type: self.type,
			status: self.status,
			tags: self.tags
		}
		values[:ack] = self.ack.to_h if self.ack

		return values
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

	### Return a string describing the node's status.
	def status_description
		case self.status
		when 'up', 'down'
			return "%s as of %s" % [ self.status.upcase, self.last_contacted ]
		when 'acked'
			return "ACKed by %s %s" % [ self.ack.sender, self.ack.time.as_delta ]
		when 'disabled'
			return "disabled by %s %s" % [ self.ack.sender, self.ack.time.as_delta ]
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
		return "#<%p:%#x [%s] -> %s %p %s%s, %d children, %s>" % [
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

	### Return a Hash of the node's state.
	def to_hash
		return {
			identifier: self.identifier,
			type: self.class.name.to_s.sub( /.+::/, '' ).downcase,
			parent: self.parent,
			description: self.description,
			tags: self.tags,
			properties: self.properties.dup,
			status: self.status,
			ack: self.ack ? self.ack.to_h : nil,
			last_contacted: self.last_contacted ? self.last_contacted.iso8601 : nil,
			status_changed: self.status_changed ? self.status_changed.iso8601 : nil,
			error: self.error,
		}
	end


	### Marshal API -- return the node as an object suitable for marshalling.
	def marshal_dump
		return self.to_hash
	end


	### Marshal API -- set up the object's state using the +hash+ from a
	### previously-marshalled node.
	def marshal_load( hash )
		@identifier = hash[:identifier]
		@properties = hash[:properties]

		@parent         = hash[:parent]
		@description    = hash[:description]
		@tags           = Set.new( hash[:tags] )
		@children       = {}

		@status         = hash[:status]
		@status_changed = Time.parse( hash[:status_changed] )

		@error          = hash[:error]
		@properties     = hash[:properties]
		@last_contacted = Time.parse( hash[:last_contacted] )

		if hash[:ack]
			ack_values = hash[:ack].values_at( *Arborist::Node::ACK.members )
			@ack = Arborist::Node::ACK.new( *ack_values )
		end
	end


	### Equality operator -- returns +true+ if +other_node+ has the same identifier, parent, and
	### state as the receiving one.
	def ==( other_node )
		return \
			other_node.identifier == self.identifier &&
			other_node.parent == self.parent &&
			other_node.description == self.description &&
			other_node.tags == self.tags &&
			other_node.properties == self.properties &&
			other_node.status == self.status &&
			other_node.ack == self.ack &&
			other_node.error == self.error
	end


	#########
	protected
	#########

	### Ack the node with the specified +ack_data+, which should contain
	def ack=( ack_data )
		if ack_data
			self.log.info "Node %s ACKed with data: %p" % [ self.identifier, ack_data ]
			ack_data['time'] ||= Time.now
			ack_values = ack_data.values_at( *Arborist::Node::ACK.members.map(&:to_s) )
			new_ack = Arborist::Node::ACK.new( *ack_values )

			if missing = ACK_REQUIRED_PROPERTIES.find {|prop| new_ack[prop].nil? }
				raise "Missing required ACK attribute %s" % [ missing ]
			end

			@ack = new_ack
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


	### State machine guard predicate -- Returns +true+ if the last time the node
	### was monitored resulted in an update.
	def last_contact_successful?
		self.log.debug "Checking to see if last contact was successful (it %s)" %
			[ self.error ? "wasn't" : "was" ]
		return !self.error
	end


	#
	# :section: State Callbacks
	#

	### Log every status transition
	def log_transition( transition )
		self.log.debug "Transitioned %s from %s to %s" %
			[ self.identifier, transition.from, transition.to ]
	end


	### Callback for when an acknowledgement is set.
	def on_ack( transition )
		self.log.warn "ACKed: %s" % [ self.status_description ]
		self.pending_update_events <<
			Arborist::Event.create( 'node_acked', self.fetch_values, self.ack.to_h )
	end


	### Callback for when an acknowledgement is cleared.
	def on_ack_cleared( transition )
		self.error = nil
		self.log.warn "ACK cleared for %s" % [ self.identifier ]
	end


	### Callback for when a node goes from down to up
	def on_node_up( transition )
		self.error = nil
		self.log.warn "%s is %s" % [ self.identifier, self.status_description ]
	end


	### Callback for when a node goes from up to down
	def on_node_down( transition )
		self.log.error "%s is %s" % [ self.identifier, self.status_description ]
		self.update_delta[ 'error' ] = [ nil, self.error ]
	end


	### Callback for when a node goes from up to disabled
	def on_node_disabled( transition )
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

	### Returns true if the specified +hash+ includes the specified +key+, and the value
	### associated with the +key+ either includes +val+ if it is a Hash, or equals +val+ if it's
	### anything but a Hash.
	def hash_matches( hash, key, val )
		actual = hash[ key ] or return false

		if actual.is_a?( Hash )
			if val.is_a?( Hash )
				return val.all? {|subkey, subval| hash_matches(actual, subkey, subval) }
			else
				return false
			end
		else
			return actual == val
		end
	end

end # class Arborist::Node
