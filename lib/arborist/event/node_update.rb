#!/usr/bin/env ruby

require 'arborist/node' unless defined?( Arborist::Node )


# An event sent on every node update, regardless of whether or not the update resulted in
# any changes
class Arborist::Event::NodeUpdate < Arborist::Event


	### Create a NodeUpdate event for the specified +node+.
	def initialize( node, payload=[] )
		@node = node
		super( payload )
	end


	# The object's node
	attr_reader :node


	### Returns +true+ if the specified +object+ matches this event.
	def match( object )
		return super &&
			object.respond_to?( :criteria ) && self.node.matches?( object.criteria )
	end

end # class Arborist::Event::NodeUpdate
