# -*- ruby -*-
#encoding: utf-8

require 'arborist/event' unless defined?( Arborist::Event )
require 'arborist/event/node_matching'


# An event sent when one or more attributes of a node changes.
class Arborist::Event::NodeDelta < Arborist::Event
	include Arborist::Event::NodeMatching


	### Create a new NodeDelta event for the specified +node+. The +delta+
	### is a Hash of:
	###    attribute_name => [ old_value, new_value ]
	def initialize( node, delta )
		super # Overridden for the documentation
	end

end # class Arborist::Event::NodeDelta
