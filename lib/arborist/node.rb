# -*- ruby -*-
#encoding: utf-8

require 'set'
require 'uri'
require 'pathname'
require 'state_machines'

require 'loggability'
require 'pluggability'
require 'arborist' unless defined?( Arborist )
require 'arborist/mixins'


# The basic node class for an Arborist tree
class Arborist::Node
	include Enumerable
	extend Loggability,
	       Pluggability,
	       Arborist::MethodUtilities


	##
	# The key for the thread local that is used to track instances as they're
	# loaded.
	LOADED_INSTANCE_KEY = :loaded_instances

	##
	# The glob pattern to use for searching for node
	NODE_FILE_PATTERN = '**/*.rb'


	##
	# The struct for the 'ack' operational property
	ACK = Struct.new( 'ArboristNodeACK', :message, :via, :sender, :time )

	##
	# The keys required to be set for an ACK
	ACK_REQUIRED_PROPERTIES = %i[ message sender ]


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
			:acked

		event :update do
			transition any - [:acked] => :acked, if: :ack_set?
			transition any - [:up] => :up, if: :last_contact_successful?
			transition any - [:down, :acked] => :down, unless: :last_contact_successful?
		end

		after_transition :acked => :up, do: :on_ack_cleared
		after_transition :down => :up, do: :on_node_up
		after_transition :up => :down, do: :on_node_down

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
		Kernel.load( file )
		return Thread.current[ LOADED_INSTANCE_KEY ]
	ensure
		Thread.current[ LOADED_INSTANCE_KEY ] = nil
	end


	### Return an iterator for all the node files in the specified +directory+.
	def self::each_in( directory )
		directory = Pathname( directory )
		return Pathname.glob( directory + NODE_FILE_PATTERN ).lazy.flat_map do |file|
			file_url = "file://%s" % [ file.expand_path ]
			nodes = self.load( file )
			self.log.debug "Loaded nodes %p..." % [ nodes ]
			nodes.each do |node|
				node.source = file_url
			end
			nodes
		end
	end


	### Create a new Node with the specified +identifier+, which must be unique to the
	### loaded tree.
	def initialize( identifier, options={}, &block )
		raise "Invalid identifier %p" % [identifier] unless
			identifier =~ /^\w[\w\-]*$/

		@identifier     = identifier
		@options        = options
		@parent         = nil
		@description    = nil
		@tags           = Set.new
		@source         = nil
		@children       = {}

		@status         = 'unknown'
		@status_changed = nil

		@error          = nil
		@ack            = nil
		@properties     = {}
		@last_contacted = Time.at( 0 )

		self.instance_eval( &block ) if block
	end


	######
	public
	######

	##
	# The node's identifier
	attr_reader :identifier

	##
	# The node's options
	attr_reader :options

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
		@tags.merge( tags ) unless tags.empty?
		return @tags
	end


	### Update specified +properties+ for the node.
	def update( properties )
		self.log.debug "Updated: %p" % [ properties ]

		self.last_contacted = Time.now
		self.error          = properties.delete( :error )
		self.ack            = properties.delete( :ack ) if properties.key?( :ack )

		self.properties.merge!( properties, &method(:deep_merge_hash) )

		super
	end


	### Ack the node with the specified +ack_data+, which should contain
	def ack=( ack_data )
		self.log.debug "ACKed with data: %p" % [ ack_data ]
		ack_values = ack_data.values_at( *Arborist::Node::ACK.members )
		self.log.debug "  ack values: %p" % [ ack_values ]
		new_ack = Arborist::Node::ACK.new( *ack_values )

		if missing = ACK_REQUIRED_PROPERTIES.find {|prop| new_ack[prop].nil? }
			raise "Missing required ACK attribute %s" % [ missing ]
		end

		@ack = new_ack
	end


	### Returns +true+ if the node has an ACK status set.
	def ack_set?
		return @ack ? true : false
	end


	### Returns +true+ if the last time the node was monitored resulted in an
	### update.
	def last_contact_successful?
		return !self.error
	end


	#
	# :section: State Callbacks
	#

	### Callback for when an acknowledgement is cleared.
	def on_ack_cleared
		# :TODO: Currently a no-op, but send an event when we know how to do that.
	end


	### Callback for when a node goes from down to up
	def on_node_up
		# :TODO: Currently a no-op, but send an event when we know how to do that.
	end


	### Callback for when a node goes from up to down
	def on_node_down
		# :TODO: Currently a no-op, but send an event when we know how to do that.
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
	# State maintenance methods
	#


	### Return a String representation of the object suitable for debugging.
	def inspect
		return "#<%p:%#x [%s] -> %s %p %s, %d children>" % [
			self.class,
			self.object_id * 2,
			self.identifier,
			self.parent || 'root',
			self.description || "(no description)",
			self.source,
			self.children.length,
		]
	end


	#######
	private
	#######

	### Merge conflict block for doing recursive Hash#merge!
	def deep_merge_hash( key, oldval, newval )
		if oldval.respond_to?(:merge) && newval.respond_to?(:merge)
			oldval.merge( newval, &method(:deep_merge_hash) )
		else
			newval
		end
	end

end # class Arborist::Node
