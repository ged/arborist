# -*- ruby -*-
#encoding: utf-8

require 'loggability'
require 'rbczmq'
require 'arborist/manager' unless defined?( Arborist::Manager )


class Arborist::Manager::EventPublisher < ZMQ::Handler
	extend Loggability,
	       Arborist::MethodUtilities

	# Loggability API -- log to arborist's logger
	log_to :arborist


	### Create a new EventPublish that will publish events emitted by
	### emitters on the specified +manager+ on the given +pollable+.
	def initialize( pollitem, manager, reactor )
		self.log.debug "Setting up a %p" % [ self.class ]
		@pollitem    = pollitem
		@manager     = manager
		@reactor     = reactor
		@registered  = true
		@event_queue = []
	end


	######
	public
	######

	##
	# True if the publisher is currently registered with the reactor (i.e., waiting
	# to write published events).
	attr_predicate :registered


	### Publish the specified +event+.
	def <<( event )
		@event_queue << event
		self.register
		return self
	end


	### ZMQ::Handler API -- write events to the socket as it becomes writable.
	def on_writable
		unless @event_queue.empty?
			event = @event_queue.shift
			self.send( event.to_s )
		end
		self.unregister if @event_queue.empty?
		return true
	end


	#########
	protected
	#########

	### Register the publisher with the reactor if it's not already.
	def register
		@reactor.register( self.pollitem.pollable ) unless @registered
		@registered = true
	end


	### Unregister the publisher from the reactor if it's registered.
	def unregister
		@reactor.remove( self.pollitem.pollable ) if @registered
		@registered = false
	end


end # class Arborist::Manager::EventPublisher

