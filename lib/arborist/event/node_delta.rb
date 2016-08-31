# -*- ruby -*-
#encoding: utf-8

require 'arborist/event' unless defined?( Arborist::Event )
require 'arborist/event/node'
require 'arborist/mixins'


# An event sent when one or more attributes of a node changes.
class Arborist::Event::NodeDelta < Arborist::Event::Node
	include Arborist::HashUtilities


	### Create a new NodeDelta event for the specified +node+. The +delta+
	### is a Hash of:
	###    attribute_name => [ old_value, new_value ]
	def initialize( node, delta )
		super # Overridden for the documentation
	end


	### Overridden so delta events only contain the diff of attributes that changed.
	def payload
		return @payload
	end


	### Returns +true+ if the specified +object+ matches this event.
	def match( object )
		rval = super &&
			self.delta_matches?( object.criteria ) &&
			!self.delta_matches?( object.negative_criteria, if_empty: false )
		self.log.debug "Delta event #match: %p" % [ rval ]
		return rval
	end


	### Returns +true+ if the 'delta' value of the specified +criteria+ (which
	### must respond to .all?) matches the delta this event represents. If the specified
	### criteria doesn't contain any `delta` criteria, the +default+ value is used instead.
	def delta_matches?( criteria, if_empty: true )
		self.log.debug "Delta matching %p (%p if empty)" % [ criteria, if_empty ]
		delta_criteria = criteria['delta']
		return if_empty if !delta_criteria || delta_criteria.empty?

		self.log.debug "Matching event against delta criteria: %p" % [ delta_criteria ]

		return delta_criteria.all? do |key, val|
			self.log.debug "  matching %p: %p against %p" % [ key, val, self.payload ]
			hash_matches( self.payload, key, val )
		end.tap {|match| self.log.debug "  event delta %s match." % [ match ? "DID" : "did not"] }
	end

end # class Arborist::Event::NodeDelta
