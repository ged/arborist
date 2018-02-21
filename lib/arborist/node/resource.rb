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

		attributes[ :category ] ||= identifier
		super( qualified_identifier, host, attributes, &block )
	end


	### Set service +attributes+.
	def modify( attributes )
		attributes = stringify_keys( attributes )
		super
		self.category( attributes['category'] )
	end


	### Return a Hash of the operational values that are included with the node's
	### monitor state.
	def operational_values
		return super.merge(
			addresses: self.addresses.map( &:to_s )
		)
	end


	### Get/set the resource category.
	def category( new_category=nil )
		return @category unless new_category
		@category = new_category
	end


	### Delegate the resources's address to its host.
	def addresses
		return @host.addresses
	end


	### Delegate the resource's hostname to it's parent host.
	def hostname
		return @host.hostname
	end


	### Overridden to disallow modification of a Resource parent, as it needs a
	### reference to the Host node for delegation.
	def parent( new_parent=nil )
		return super unless new_parent
		raise "Can't reparent a resource; replace the node instead"
	end


	### Serialize the resource node.  Return a Hash of the host node's state.
	def to_h( * )
		return super.merge(
			addresses: self.addresses.map( &:to_s ),
			category: self.category
		)
	end


	### Returns +true+ if the node matches the specified +key+ and +val+ criteria.
	def match_criteria?( key, val )
		self.log.debug "Matching %p: %p against %p" % [ key, val, self ]
		return case key
			when 'address'
				search_addr = IPAddr.new( val )
				self.addresses.any? {|a| search_addr.include?(a) }
			when 'category'
				self.category == val
			else
				super
			end
	end

end # class Arborist::Node::Resource
