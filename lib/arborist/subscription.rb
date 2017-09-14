# -*- ruby -*-
#encoding: utf-8

require 'loggability'
require 'securerandom'

require 'arborist' unless defined?( Arborist )
require 'arborist/mixins'


# An observer subscription to node events.
class Arborist::Subscription
	extend Loggability
	include Arborist::HashUtilities


	# Loggability API -- log to the Arborist logger
	log_to :arborist


	### Instantiate a new Subscription object given an +event+ pattern
	### and event +criteria+.
	def initialize( event_type=nil, criteria={}, negative_criteria={}, &callback )
		@callback   = callback
		@event_type = event_type
		@criteria   = stringify_keys( criteria )
		@negative_criteria = stringify_keys( negative_criteria )

		self.check_callback

		@id         = self.generate_id
	end


	######
	public
	######

	# The callable that should be called when the subscription receives a matching event
	attr_reader :callback

	# A unique identifier for this subscription request.
	attr_reader :id

	# The Arborist event pattern that this subscription handles.
	attr_reader :event_type

	# Node selection attributes to require
	attr_reader :criteria

	# Node selection attributes to exclude
	attr_reader :negative_criteria


	### Add the given +criteria+ hash to the #negative_criteria.
	def exclude( criteria )
		criteria = stringify_keys( criteria )
		self.negative_criteria.merge!( criteria )
	end


	### Check to make sure the subscription will function as it's set up.
	def check_callback
		raise LocalJumpError, "requires a callback block" unless self.callback
	end


	### Publish any of the specified +events+ which match the subscription.
	def on_events( *events )
		events.flatten.each do |event|
			if self.interested_in?( event )
				self.log.debug "Calling %p for a %s event" % [ self.callback, event.type ]
				self.callback.call( self.id, event )
			end
		end
	end


	### Return a String representation of the object suitable for debugging.
	def inspect
		return "#<%p:%#x [%s] for %s events matching: %p %s-> %p>" % [
			self.class,
			self.object_id * 2,
			self.id,
			self.event_type,
			self.criteria,
			self.negative_criteria.empty? ? '' : "(but not #{self.negative_criteria.inspect}",
			self.callback,
		]
	end


	### Create an identifier for this subscription object.
	def generate_id
		return SecureRandom.uuid
	end


	### Returns +true+ if the receiver is interested in publishing the specified +event+.
	def interested_in?( event )
		self.log.debug "Testing %p against type = %p and criteria = %p but not %p" %
			[ event, self.event_type, self.criteria, self.negative_criteria ]
		rval = event.match( self )
		self.log.debug "  event %s match." % [ rval ? "did" : "did NOT" ]
		return rval
	end
	alias_method :is_interested_in?, :interested_in?

end # class Arborist::Subscription
