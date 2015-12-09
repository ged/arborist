# -*- ruby -*-
#encoding: utf-8

require 'arborist/event' unless defined?( Arborist::Event )
require 'arborist/event/node_matching'


# An event generated when a node is manually ACKed.
class Arborist::Event::NodeAcked < Arborist::Event
	include Arborist::Event::NodeMatching


	### Create a new NodeAcked event for the specified +node+ and +ack_info+.
	def initialize( node, ack_info )
		super
	end

end # class Arborist::Event::NodeAcked
