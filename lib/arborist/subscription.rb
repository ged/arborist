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
	def initialize( publisher, event_type=nil, criteria={} )
		@publisher  = publisher
		@event_type = event_type
		@criteria   = stringify_keys( criteria )
		@id         = self.generate_id
	end


	######
	public
	######

	# The Arborist::Manager::EventPublisher the subscription will use to publish matching events.
	attr_reader :publisher

	# A unique identifier for this subscription request.
	attr_reader :id

	# The Arborist event pattern that this subscription handles.
	attr_reader :event_type

	# Node selection attributes to match
	attr_reader :criteria


	### Create an identifier for this subscription object.
	def generate_id
		return SecureRandom.uuid
	end


	### Publish any of the specified +events+ which match the subscription.
	def on_events( *events )
		events.flatten.each do |event|
			self.publisher.publish( self.id, event ) if self.interested_in?( event )
		end
	end


	### Returns +true+ if the receiver is interested in publishing the specified +event+.
	def interested_in?( event )
		self.log.debug "Testing %p against type = %p and criteria = %p" %
			[ event, self.event_type, self.criteria ]
		return event.match( self )
	end
	alias_method :is_interested_in?, :interested_in?


	### Return a String representation of the object suitable for debugging.
	def inspect
		return "#<%p:%#x [%s] for %s events matching: %p>" % [
			self.class,
			self.object_id * 2,
			self.id,
			self.event_type,
			self.criteria,
		]
	end

end # class Arborist::Subscription
