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
		def initialize( runner, reactor )
			@runner = runner
			@client = Arborist::Client.new
			@pollitem = ZMQ::Pollitem.new( @client.event_api, ZMQ::POLLIN )
			@pollitem.handler = self
			@subscriptions = {}

			reactor.register( @pollitem )
		end


		######
		public
		######

		# The Arborist::ObserverRunner that owns this handler.
		attr_reader :runner

		# The Arborist::Client that will be used for creating and tearing down subscriptions
		attr_reader :client

		# The map of subscription IDs to the Observer which it was created for.
		attr_reader :subscriptions


		### Unsubscribe from and clear all current subscriptions.
		def reset
			self.log.warn "Resetting the observer handler."
			self.subscriptions.keys.each do |subid|
				self.client.event_api.unsubscribe( subid )
			end
			self.subscriptions.clear
		end


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
			event = MessagePack.unpack( raw_event )

			if (( observer = self.subscriptions[subid] ))
				observer.handle_event( subid, event )
			elsif subid.start_with?( 'sys.' )
				self.log.debug "System event! %p" % [ event ]
				self.runner.handle_system_event( subid, event )
			else
				self.log.warn "Ignoring event %p for which we have no observer." % [ subid ]
			end

			return true
		end

	end # class Handler


	### Create a new Arborist::ObserverRunner
	def initialize
		@observers = []
		@timers = []
		@handler = nil
		@reactor = ZMQ::Loop.new
		@manager_last_runid = nil
	end


	######
	public
	######

	# The Array of loaded Arborist::Observers the runner should run.
	attr_reader :observers

	# The Array of registered ZMQ::Timers
	attr_reader :timers

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
		self.handler = Arborist::ObserverRunner::Handler.new( self, self.reactor )

		self.register_observers
		self.register_observer_timers
		self.subscribe_to_system_events

		self.reactor.start
	rescue Interrupt
		$stderr.puts "Interrupted!"
		self.stop
	end


	### Stop the observer
	def stop
		self.observers.each do |observer|
			self.remove_timers
			self.handler.remove_observer( observer )
		end

		self.reactor.stop
	end


	### Register each of the runner's Observers with its handler.
	def register_observers
		self.observers.each do |observer|
			self.handler.add_observer( observer )
		end
	end


	### Register timers for each Observer.
	def register_observer_timers
		self.observers.each do |observer|
			self.add_timers_for( observer )
		end
	end


	### Subscribe the runner to system events published by the Manager.
	def subscribe_to_system_events
		self.handler.client.event_api.subscribe( 'sys.' )
	end


	### Register a timer for the specified +observer+.
	def add_timers_for( observer )
		observer.timers.each do |interval, callback|
			self.log.info "Creating timer for %s observer to run %p every %ds" %
				[ observer.description, callback, interval ]
			timer = ZMQ::Timer.new( interval, 0, &callback )
			self.reactor.register_timer( timer )
			self.timers << timer
		end
	end


	### Remove any registered timers.
	def remove_timers
		self.timers.each do |timer|
			self.reactor.cancel_timer( timer )
		end
	end


	### Handle a `sys.` event from the Manager being observed.
	def handle_system_event( event_type, event )
		self.log.debug "Got a %s event from the Manager: %p" % [ event_type, event ]

		case event_type
		when 'sys.heartbeat'
			this_runid = event['run_id']
			if @manager_last_runid && this_runid != @manager_last_runid
				self.log.warn "Manager run ID changed: re-subscribing"
				self.handler.reset
				self.register_observers
			end

			@manager_last_runid = this_runid
		when 'sys.node_added', 'sys.node_removed'
			# no-op
		else
			# no-op
		end
	end

end # class Arborist::ObserverRunner

