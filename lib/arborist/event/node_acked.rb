# -*- ruby -*-
#encoding: utf-8

require 'arborist/event' unless defined?( Arborist::Event )
require 'arborist/event/node_update'


# An event generated when a node is manually ACKed.
class Arborist::Event::NodeAcked < Arborist::Event::NodeUpdate

	### Create a new NodeAcked event for the specified +node+ and +ack_info+.
	def initialize( node, ack_info )
		super( node, ack_info )
	end


	alias_method :ack_info, :payload


end # class Arborist::Event::NodeAcked
