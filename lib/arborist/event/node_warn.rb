# -*- ruby -*-
#encoding: utf-8

require 'arborist/event' unless defined?( Arborist::Event )
require 'arborist/event/node'


# An event generated when a monitor adds the first warning to a node.
class Arborist::Event::NodeWarn < Arborist::Event::Node

	### Create a new NodeWarn event for the specified +node+.
	def initialize( node )
		super( node, node.warnings.to_h )
	end

end # class Arborist::Event::NodeWarn
