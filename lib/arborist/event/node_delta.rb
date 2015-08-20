# -*- ruby -*-
#encoding: utf-8

require 'arborist/event' unless defined?( Arborist::Event )
require 'arborist/event/node_update'


# An event sent when one or more attributes of a node changes.
class Arborist::Event::NodeDelta < Arborist::Event::NodeUpdate

	### Create a new NodeDelta event for the specified +node+. The +delta+
	### is a Hash of:
	###    attribute_name => [ old_value, new_value ]
	def initialize( node, delta )
		super( node, delta )
	end


	alias_method :delta, :payload


end # class Arborist::Event::NodeDelta
