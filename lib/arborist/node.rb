# -*- ruby -*-
#encoding: utf-8

require 'set'
require 'uri'
require 'pathname'

require 'loggability'
require 'pluggability'
require 'arborist' unless defined?( Arborist )


# The basic node class for an Arborist tree
class Arborist::Node
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
	# Log via the Arborist logger
	log_to :arborist

	##
	# Search for plugins in lib/arborist/node directories in loaded gems
	plugin_prefixes 'arborist/node'


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

		name = subclass.name.sub( /.*::/, '' )
		body = self.curried_create( subclass )

		Arborist.add_dsl_constructor( name, &body )
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
		@identifier  = identifier
		@options     = options
		@parent      = nil
		@description = nil
		@tags        = Set.new
		@source      = nil

		self.instance_eval( &block )
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
		self.log.debug "description( %p )" % [ new_description ]
		return @description unless new_description
		@description = new_description.to_s
	end


	### Declare one or more +tags+ for this node.
	def tags( *tags )
		@tags.merge( tags ) unless tags.empty?
		return @tags
	end


	#
	# :section:
	#


	### Set the source of the node to +source+, which should be a valid URI.
	def source=( source )
		@source = URI( source )
	end


	### Return a String representation of the object suitable for debugging.
	def inspect
		return "#<%p:%#x [%s] %p %s>" % [
			self.class,
			self.object_id * 2,
			self.identifier,
			self.description || "(no description)",
			self.source,
		]
	end

end # class Arborist::Node
