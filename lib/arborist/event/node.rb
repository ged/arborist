# -*- ruby -*-
#encoding: utf-8

require 'arborist/event' unless defined?( Arborist::Event )


# A base class for events which are related to an Arborist::Node.
class Arborist::Event::Node < Arborist::Event

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
		rval = super &&
			self.node.matches?( object.criteria ) &&
			!self.node.matches?( object.negative_criteria, if_empty: false )
		self.log.debug "Node event #match: %p" % [ rval ]
		return rval
	end


	### Use the node data as this event's payload.
	def payload
		return self.node.to_h
	end


	### Inject the node identifier into the generated hash.
	def to_h
		return super.merge(
			identifier: self.node.identifier,
			parent:     self.node.parent
		)
	end

end # module Arborist::Event::NodeMatching

