# -*- ruby -*-
#encoding: utf-8

require 'rbczmq'
require 'loggability'

require 'arborist' unless defined?( Arborist )
require 'arborist/client'
require 'arborist/observer'


# Undo the useless scoping
class ZMQ::Loop
	public_class_method :instance
end


# An event-driven runner for Arborist::Observers.
class Arborist::ObserverRunner
	extend Loggability

	log_to :arborist


	# A ZMQ::Handler object for managing IO for all running observers.
	class Handler < ZMQ::Handler
		extend Loggability,
		       Arborist::MethodUtilities

		log_to :arborist

		### Create a ZMQ::Handler that acts as the agent that runs the specified
		### +observer+.
		def initialize( reactor )
			@client = Arborist::Client.new
			@pollitem = ZMQ::Pollitem.new( @client.event_api, ZMQ::POLLIN )
			@pollitem.handler = self
			@subscriptions = {}

			reactor.register( @pollitem )
		end


		######
		public
		######

		# The Arborist::Client that will be used for creating and tearing down subscriptions
		attr_reader :client

		# The map of subscription IDs to the Observer which it was created for.
		attr_reader :subscriptions


		### Add the specified +observer+ and subscribe to the events it wishes to receive.
		def add_observer( observer )
			self.log.info "Adding observer: %s" % [ observer.description ]
			observer.subscriptions.each do |sub|
				subid = self.client.subscribe( sub )
				self.subscriptions[ subid ] = observer
				self.client.event_api.subscribe( subid )
				self.log.debug "  subscribed to %p with subscription %s" % [ sub, subid ]
			end
		end


		### Remove the specified +observer+ after unsubscribing from its events.
		def remove_observer( observer )
			self.log.info "Removing observer: %s" % [ observer.description ]

			self.subscriptions.keys.each do |subid|
				next unless self.subscriptions[ subid ] == observer

				self.client.unsubscribe( subid )
				self.subscriptions.delete( subid )
				self.client.event_api.unsubscribe( subid )
				self.log.debug "  unsubscribed from %p" % [ subid ]
			end
		end


		### Read events from the event socket when it becomes readable, and dispatch them to
		### the correct observer.
		def on_readable
			subid = self.recv
			raise "Partial write?!" unless self.pollitem.pollable.rcvmore?
			raw_event = self.recv

			if (( observer = self.subscriptions[subid] ))
				event = MessagePack.unpack( raw_event )
				observer.handle_event( subid, event )
			else
				self.log.warn "Ignoring event %p for which we have no observer." % [ subid ]
			end

			return true
		end

	end # class Handler


	### Create a new Arborist::ObserverRunner
	def initialize
		@observers = []
		@handler = nil
		@reactor = ZMQ::Loop.new
	end


	######
	public
	######

	# The Array of loaded Arborist::Observers the runner should run.
	attr_reader :observers

	# The ZMQ::Handler subclass that handles all async IO
	attr_accessor :handler

	# The reactor (a ZMQ::Loop) the runner uses to drive everything
	attr_accessor :reactor


	### Load observers from the specified +enumerator+.
	def load_observers( enumerator )
		@observers += enumerator.to_a
	end


	### Run the specified +observers+
	def run
		self.handler = Arborist::ObserverRunner::Handler.new( self.reactor )

		self.observers.each do |observer|
			self.handler.add_observer( observer )
			self.add_timers_for( observer )
		end

		self.reactor.start
	rescue Interrupt
		$stderr.puts "Interrupted!"
		self.stop
	end


	### Stop the observer
	def stop
		self.observers.each do |observer|
			# :TODO: Remove timers associated with this observer
			self.handler.remove_observer( observer )
		end

		self.reactor.stop
	end


	# :MAHLON: For periodic/rollup/etc. we could do something like this:

	### Register a timer for the specified +observer+.
	def add_timers_for( observer )
		# observer.timers.each do |interval, callback|
		# 	timer = ZMQ::Timer.new( interval, 0, &callback )
		# 	self.reactor.register_timer( timer )
		# end
	end


end # class Arborist::ObserverRunner

