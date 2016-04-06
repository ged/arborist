# -*- ruby -*-
#encoding: utf-8

require 'arborist/event' unless defined?( Arborist::Event )
require 'arborist/event/node'


# An event generated when a node is manually disabled
class Arborist::Event::NodeDisabled < Arborist::Event::Node

	### Create a new NodeDisabled event for the specified +node+.
	def initialize( node )
		super( node, node.ack.to_h )
	end

end # class Arborist::Event::NodeDisabled
