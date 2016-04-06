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



	### Returns +true+ if the specified +object+ matches this event.
	def match( object )
		return super &&
			object.respond_to?( :criteria ) && self.delta_matches?( object.criteria )
	end


	### Returns +true+ if the 'delta' value of the specified +criteria+ (which
	### must respond to .all?) matches the delta this event represents.
	def delta_matches?( criteria )
		delta_criteria = criteria['delta'] || {}
		self.log.debug "Matching event against delta criteria: %p" % [ delta_criteria ]

		return delta_criteria.all? do |key, val|
			self.log.debug "  matching %p: %p against %p" % [ key, val, self.payload ]
			hash_matches( self.payload, key, val )
		end.tap {|match| self.log.debug "  event delta %s match." % [ match ? "DID" : "did not"] }
	end

end # class Arborist::Event::NodeDelta
