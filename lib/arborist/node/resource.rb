# -*- ruby -*-
#encoding: utf-8

require 'arborist/node'
require 'arborist/mixins'


# A node type for Arborist trees that represent arbitrary resources of a host.
class Arborist::Node::Resource < Arborist::Node

	# Services live under Host nodes
	parent_type :host


	### Create a new Resource node.
	def initialize( identifier, host, attributes={}, &block )
		raise Arborist::NodeError, "no host given" unless host.is_a?( Arborist::Node::Host )
		qualified_identifier = "%s-%s" % [ host.identifier, identifier ]

		@host = host

		super( qualified_identifier, host, attributes, &block )
	end


	### Overridden to disallow modification of a Resource parent, as it needs a
	### reference to the Host node for delegation.
	def parent( new_parent=nil )
		return super unless new_parent
		raise "Can't reparent a resource; replace the node instead"
	end

end # class Arborist::Node::Resource
