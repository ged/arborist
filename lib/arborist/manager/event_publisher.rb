# -*- ruby -*-
#encoding: utf-8

require 'loggability'
require 'rbczmq'
require 'arborist/manager' unless defined?( Arborist::Manager )


class Arborist::Manager::EventPublisher < ZMQ::Handler
	extend Loggability

	# Loggability API -- log to arborist's logger
	log_to :arborist


	### Create a new EventPublish that will publish events emitted by
	### emitters on the specified +manager+ on the given +pollable+.
	def initialize( pollable, manager )
		self.log.debug "Setting up a %p" % [ self.class ]
		super
		@manager = manager
		@event_queue = []
	end


	### ZMQ::Handler API -- write events to the socket as it becomes writable.
	def on_writable
		event = @event_queue.shift or return
		self.send( event.to_s )
	end

end # class Arborist::Manager::EventPublisher

