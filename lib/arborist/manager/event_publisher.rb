# -*- ruby -*-
#encoding: utf-8

require 'msgpack'
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
		self.log.debug "Setting up a %p for %p (socket %p)" %
			[ self.class, pollitem, pollitem.pollable ]
		@pollable    = pollitem.pollable
		@pollitem    = pollitem
		@manager     = manager
		@reactor     = reactor
		@registered  = true
		@enabled     = true
		@event_queue = []
	end


	######
	public
	######

	##
	# True if the publisher is currently registered with the reactor (i.e., waiting
	# to write published events).
	attr_predicate :registered

	##
	# The Queue of pending events to publish
	attr_reader :event_queue

	##
	# A on/off toggle for publishing events
	attr_predicate :enabled


	### Publish the specified +event+.
	def publish( identifier, event )
		return self unless self.enabled?
		@event_queue << [ identifier, MessagePack.pack(event.to_h) ]
		self.register
		return self
	end


	### ZMQ::Handler API -- write events to the socket as it becomes writable.
	def on_writable
		unless @event_queue.empty?
			tuple = @event_queue.shift
			identifier, payload = *tuple

			pollsocket = self.pollitem.pollable
			pollsocket.sendm( identifier )
			pollsocket.send( payload )
		end
		self.unregister if @event_queue.empty?
		return true
	end


	### Stop accepting events to be published
	def shutdown
		@enabled = false
		return if @event_queue.empty?

		start   = Time.now
		timeout = start + (@manager.linger.to_f / 2000)

		self.log.warn "Waiting to empty the event queue..."
		until @event_queue.empty?
			sleep 0.1
			break if Time.now > timeout
		end
		self.log.warn "  ... waited %0.1f seconds" % [ Time.now - start ]
	end



	#########
	protected
	#########

	### Register the publisher with the reactor if it's not already.
	def register
		count ||= 0
		@reactor.register( self.pollitem ) unless @registered
		# self.log.info "Publisher socket is now registered!"
		@registered = true
	rescue => err
		# :TODO:
		# This is to work around a weird error that happens sometimes when registering:
		#   Sys error location: loop.c:424
		# which then raises a RuntimeError with "Socket operation on non-socket". This is
		# probably due to a race somewhere, but we can't find it. So this works (at least
		# for the specs) in the meantime.
		raise unless err.message.include?( "Socket operation on non-socket" )
		count += 1
		raise "Gave up trying to register %p with the reactor" % [ self.pollitem ] if count > 5
		warn "Retrying registration!"
		retry
	end


	### Unregister the publisher from the reactor if it's registered.
	def unregister
		@reactor.remove( self.pollitem ) if @registered
		@registered = false
	end


end # class Arborist::Manager::EventPublisher

