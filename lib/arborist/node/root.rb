# -*- ruby -*-
#encoding: utf-8

require 'arborist/node' unless defined?( Arborist::Node )
require 'arborist/mixins'


# The class of the root node of an Arborist tree. This class is a Singleton.
class Arborist::Node::Root < Arborist::Node
	extend Arborist::MethodUtilities


	# The instance of the Root node.
	@instance = nil

	### Create the instance of the Root node (if necessary) and return it.
	def self::new( * )
		@instance ||= super
		return @instance
	end


	### Override the default constructor to use the singleton ::instance instead.
	def self::instance( * )
		@instance ||= new
		return @instance
	end


	### Reset the singleton instance; mainly used for testing.
	def self::reset
		@instance = nil
	end


	### Set up the root node.
	def initialize( * )
		super( '_' ) do
			description "The root node."
			source = URI( __FILE__ )
		end

		@status = 'up'
		@status.freeze
	end


	### Ignore restores of serialized root nodes.
	def restore( other_node )
		self.log.info "Ignoring restored root node."
	end


	### Don't allow properties to be set on the root node.
	def update( properties, monitor_key='_' )
		return super( {} )
	end


	### Callback for when a node goes from disabled to unknown.
	### Override, so we immediately transition from unknown to up.
	def on_node_enabled( transition )
		super
		events = self.update( {} ) # up!
		self.publish_events( events )
	end


	### Override the reader mode of Node#parent for the root node, which never has
	### a parent.
	def parent( * )
		return nil
	end

end # class Arborist::Node::Root
