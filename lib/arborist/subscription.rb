# -*- ruby -*-
#encoding: utf-8

require 'securerandom'

require 'arborist' unless defined?( Arborist )
require 'arborist/mixins'


# An observer subscription to node events.
class Arborist::Subscription
	include Arborist::HashUtilities

	### Instantiate a new Subscription object given an +event+ pattern
	### and event +criteria+.
	def initialize( event_type, criteria={} )
		@event_type = event_type
		@criteria   = stringify_keys( criteria )
		@id         = self.generate_id
	end


	# A unique identifier for this subscription request.
	attr_reader :id

	# The Arborist event pattern that this subscription handles.
	attr_reader :event_type

	# Node selection attributes to match and emit upon.
	attr_reader :criteria


	### Create an identifier for this subscription object.
	def generate_id
		return SecureRandom.uuid
	end

end # class Arborist::Subscription
