# -*- ruby -*-
#encoding: utf-8

require 'arborist/event' unless defined?( Arborist::Event )
require 'arborist/event/node'


# An event generated when a node is manually ACKed.
class Arborist::Event::NodeAcked < Arborist::Event::Node

	### Create a new NodeAcked event for the specified +node+.
	def initialize( node )
		super( node, node.ack.to_h )
	end

end # class Arborist::Event::NodeAcked
