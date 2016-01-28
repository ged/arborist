# -*- ruby -*-
#encoding: utf-8

require 'arborist/event' unless defined?( Arborist::Event )


# A mixin which adds common functionality to events which related to an
# Arborist::Node.
module Arborist::Event::NodeMatching

	### Strip and save the node argument to the constructor.
	def initialize( node, payload=nil )
		@node = node
		super( payload )
	end


	######
	public
	######

	# The node that generated the event
	attr_reader :node


	### Returns +true+ if the specified +object+ matches this event.
	def match( object )
		return super &&
			object.respond_to?( :criteria ) && self.node.matches?( object.criteria )
	end


	### Inject the node identifier into the generated hash.
	def to_hash
		return super.merge( identifier: self.node.identifier )
	end

end # module Arborist::Event::NodeMatching

