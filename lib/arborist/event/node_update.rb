#!/usr/bin/env ruby

require 'arborist/event' unless defined?( Arborist::Event )
require 'arborist/event/node'


# An event sent on every node update, regardless of whether or not the update resulted in
# any changes
class Arborist::Event::NodeUpdate < Arborist::Event::Node

	### Use the node data as this event's payload.
	def payload
		return self.node.to_h
	end


end # class Arborist::Event::NodeUpdate
