# -*- ruby -*-
#encoding: utf-8

require 'cztop'
require 'cztop/reactor'
require 'cztop/reactor/signal_handling'
require 'loggability'

require 'arborist' unless defined?( Arborist )
require 'arborist/client'
require 'arborist/observer'


# An event-driven runner for Arborist::Observers.
class Arborist::ObserverRunner
	extend Loggability
	include CZTop::Reactor::SignalHandling


	# Signals the observer runner responds to
	QUEUE_SIGS = [
		:INT, :TERM, :HUP,
		# :TODO: :QUIT, :WINCH, :USR1, :USR2, :TTIN, :TTOU
	] & Signal.list.keys.map( &:to_sym )


	log_to :arborist


	### Create a new Arborist::ObserverRunner
	def initialize
		@observers          = []
		@timers             = []
		@subscriptions      = {}
		@reactor            = CZTop::Reactor.new
		@client             = Arborist::Client.new
		@manager_last_runid = nil
	end


	######
	public
	######

	# The Array of loaded Arborist::Observers the runner should run.
	attr_reader :observers

	# The Array of registered ZMQ::Timers
	attr_reader :timers

	# The reactor (a CZTop::Reactor) the runner uses to drive everything
	attr_accessor :reactor

	# The Arborist::Client that will be used for creating and tearing down subscriptions
	attr_reader :client

	# The map of subscription IDs to the Observer which it was created for.
	attr_reader :subscriptions


	### Load observers from the specified +enumerator+.
	def load_observers( enumerator )
		self.observers.concat( enumerator.to_a )
	end


	### Run the specified +observers+
	def run
		self.log.info "Starting!"
		self.register_observers
		self.register_observer_timers
		self.subscribe_to_system_events

		self.reactor.register( self.client.event_api, :read, &self.method(:on_subscription_event) )

		self.with_signal_handler( self.reactor, *QUEUE_SIGS ) do
			self.reactor.start_polling( ignore_interrupts: true )
		end
	end


	### Stop the observer
	def stop
		self.log.info "Stopping!"
		self.remove_timers
		self.unregister_observers
		self.reactor.stop_polling
	end


	### Restart the observer, resetting all of its observers' subscriptions.
	def restart
		self.log.info "Restarting!"
		self.reactor.timers.pause
		self.unregister_observers

		self.register_observers
		self.reactor.timers.resume
	end


	### Returns true if the ObserverRunner is running.
	def running?
		return self.reactor &&
			self.client &&
			self.reactor.registered?( self.client.event_api )
	end


	### Add subscriptions for all of the observers loaded into the runner.
	def register_observers
		self.observers.each do |observer|
			self.add_observer( observer )
		end
	end


	### Register timers for each Observer.
	def register_observer_timers
		self.observers.each do |observer|
			self.add_timers_for( observer )
		end
	end


	### Remove the subscriptions belonging to the loaded observers.
	def unregister_observers
		self.observers.each do |observer|
			self.remove_observer( observer )
		end
	end


	### Subscribe the runner to system events published by the Manager.
	def subscribe_to_system_events
		self.client.event_api.subscribe( 'sys.' )
	end


	### Register a timer for the specified +observer+.
	def add_timers_for( observer )
		observer.timers.each do |interval, callback|
			self.log.info "Creating timer for %s observer to run %p every %ds" %
				[ observer.description, callback, interval ]
			timer = self.reactor.add_periodic_timer( interval, &callback )
			self.timers << timer
		end
	end


	### Remove any registered timers.
	def remove_timers
		self.timers.each do |timer|
			self.reactor.remove_timer( timer )
		end
	end


	### Unsubscribe from and clear all current subscriptions.
	def reset
		self.log.warn "Resetting observer subscriptions."
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


	### Handle IO events from the reactor.
	def on_subscription_event( event )
		if event.readable?
			msg = event.socket.receive
			subid, event = Arborist::EventAPI.decode( msg )

			if (( observer = self.subscriptions[subid] ))
				self.log.debug "Got %p event for %p" % [ subid, observer ]
				observer.handle_event( subid, event )
			elsif subid.start_with?( 'sys.' )
				self.log.debug "System event! %p" % [ event ]
				self.handle_system_event( subid, event )
			else
				self.log.warn "Ignoring event %p for which we have no observer." % [ subid ]
			end
		else
			raise "Unhandled event %p on the event socket" % [ event ]
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
				self.reset
				self.register_observers
			end

			@manager_last_runid = this_runid
		when 'sys.node_added', 'sys.node_removed'
			# no-op
		else
			# no-op
		end
	end


	#
	# :section: Signal Handling
	# These methods set up some behavior for starting, restarting, and stopping
	# the runner when a signal is received.
	#

	### Handle signals.
	def handle_signal( sig )
		self.log.debug "Handling signal %s" % [ sig ]
		case sig
		when :INT, :TERM
			self.on_termination_signal( sig )

		when :HUP
			self.on_hangup_signal( sig )

		else
			self.log.warn "Unhandled signal %s" % [ sig ]
		end

	end


	### Handle a TERM signal. Shuts the handler down after handling any current request/s. Also
	### aliased to #on_interrupt_signal.
	def on_termination_signal( signo )
		self.log.warn "Terminated (%p)" % [ signo ]
		self.stop
	end
	alias_method :on_interrupt_signal, :on_termination_signal


	### Handle a HUP signal. The default is to restart the handler.
	def on_hangup_signal( signo )
		self.log.warn "Hangup (%p)" % [ signo ]
		self.restart
	end


end # class Arborist::ObserverRunner

