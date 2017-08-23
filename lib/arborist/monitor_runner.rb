# -*- ruby -*-
#encoding: utf-8

require 'cztop'
require 'cztop/reactor'
require 'cztop/reactor/signal_handling'
require 'loggability'

require 'arborist' unless defined?( Arborist )
require 'arborist/client'


# An event-driven runner for Arborist::Monitors.
class Arborist::MonitorRunner
	extend Loggability
	include CZTop::Reactor::SignalHandling

	# Signals the runner handles
	QUEUE_SIGS = [
		:INT, :TERM, :HUP, :USR1,
		# :TODO: :QUIT, :WINCH, :USR2, :TTIN, :TTOU
	] & Signal.list.keys.map( &:to_sym )


	log_to :arborist


	### Create a new Arborist::MonitorRunner
	def initialize
		@monitors      = []
		@handler       = nil
		@reactor       = CZTop::Reactor.new
		@client        = Arborist::Client.new
		@request_queue = {}
	end


	######
	public
	######

	##
	# The Array of loaded Arborist::Monitors the runner should run.
	attr_reader :monitors

	##
	# The ZMQ::Handler subclass that handles all async IO
	attr_accessor :handler

	##
	# The reactor (a ZMQ::Loop) the runner uses to drive everything
	attr_accessor :reactor

	##
	# The Queue of pending requests, keyed by the callback that should be called with the
	# results.
	attr_reader :request_queue

	##
	# The Arborist::Client that will provide the message packing and unpacking
	attr_reader :client


	### Load monitors from the specified +enumerator+.
	def load_monitors( enumerator )
		self.monitors.concat( enumerator.to_a )
	end


	### Run the specified +monitors+
	def run
		self.monitors.each do |mon|
			self.add_timer_for( mon )
		end

		self.with_signal_handler( self.reactor, *QUEUE_SIGS ) do
			self.reactor.register( self.client.tree_api, :write, &self.method(:handle_io_event) )
			self.reactor.start_polling
		end
	end


	### Restart the runner
	def restart
		# :TODO: Kill any running monitor children, cancel monitor timers, and reload
		# monitors from the monitor enumerator
		raise NotImplementedError
	end


	### Stop the runner.
	def stop
		self.log.info "Stopping the runner."
		self.reactor.stop_polling
	end


	### Reactor callback -- handle the client's socket becoming writable.
	def handle_io_event( event )
		if event.writable?
			if (( pair = self.request_queue.shift ))
				callback, request = *pair
				res = self.client.send_tree_api_request( request )
				callback.call( res )
			end

			self.unregister if self.request_queue.empty?
		else
			raise "Unexpected %p on the tree API socket" % [ event ]
		end

	end


	### Run the specified +monitor+ and update nodes with the results.
	def run_monitor( monitor )
		positive     = monitor.positive_criteria
		negative     = monitor.negative_criteria
		include_down = monitor.include_down?
		props        = monitor.node_properties

		self.log.debug "Fetching node data for %p" % [ monitor ]
		self.fetch( positive, include_down, props, negative ) do |nodes|
			self.log.debug "  running the monitor for %d nodes" % [ nodes.length ]
			results = monitor.run( nodes )
			monitor_key = monitor.key

			results.each do |ident, properties|
				properties['_monitor_key'] = monitor_key
			end

			self.log.debug "  updating with results: %p" % [ results ]
			self.update( results ) do
				self.log.debug "Updated %d via the '%s' monitor" %
					[ results.length, monitor.description ]
			end
		end
	end


	### Create a fetch request using the runner's client, then queue the request up
	### with the specified +block+ as the callback.
	def fetch( criteria, include_down, properties, negative={}, &block )
		fetch = self.client.make_fetch_request( criteria,
			include_down: include_down,
			properties: properties,
			exclude: negative
		)
		self.queue_request( fetch, &block )
	end


	### Create an update request using the runner's client, then queue the request up
	### with the specified +block+ as the callback.
	def update( nodemap, &block )
		update = self.client.make_update_request( nodemap )
		self.queue_request( update, &block )
	end


	### Add the specified +event+ to the queue to be published to the console event
	### socket
	def queue_request( request, &callback )
		self.request_queue[ callback ] = request
		self.register
	end


	### Returns +true+ if the runner's client socket is currently registered for writing.
	def registered?
		return self.reactor.event_enabled?( self.client.tree_api, :write )
	end


	### Register the handler's pollitem as being ready to write if it isn't already.
	def register
		# self.log.debug "Registering for writing."
		self.reactor.enable_events( self.client.tree_api, :write ) unless self.registered?
	end


	### Unregister the handler's pollitem from the reactor when there's nothing ready
	### to write.
	def unregister
		# self.log.debug "Unregistering for writing."
		self.reactor.disable_events( self.client.tree_api, :write ) if self.registered?
	end


	### Register a timer for the specified +monitor+.
	def add_timer_for( monitor )
		interval = monitor.interval

		if monitor.splay.nonzero?
			self.add_splay_timer_for( monitor )
		else
			self.add_interval_timer_for( monitor )
		end
	end


	### Create a repeating ZMQ::Timer that will run the specified monitor on its interval.
	def add_interval_timer_for( monitor )
		interval = monitor.interval
		self.log.info "Creating timer for %p" % [ monitor ]

		return self.reactor.add_periodic_timer( interval ) do
			self.run_monitor( monitor )
		end
	end


	### Create a one-shot ZMQ::Timer that will register the interval timer for the specified
	### +monitor+ after a random number of seconds no greater than its splay.
	def add_splay_timer_for( monitor )
		delay = rand( monitor.splay )
		self.log.debug "Splaying registration of %p for %ds" % [ monitor, delay ]

		self.reactor.add_oneshot_timer( delay ) do
			self.add_interval_timer_for( monitor )
		end
	end


	#
	# :section: Signal Handling
	# These methods set up some behavior for starting, restarting, and stopping
	# the manager when a signal is received.
	#

	### Handle signals.
	def handle_signal( sig )
		self.log.debug "Handling signal %s" % [ sig ]
		case sig
		when :INT, :TERM
			self.on_termination_signal( sig )

		when :HUP
			self.on_hangup_signal( sig )

		when :USR1
			self.on_user1_signal( sig )

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


	### Handle a hangup by restarting the runner.
	def on_hangup_signal( signo )
		self.log.warn "Hangup (%p)" % [ signo ]
		self.restart
	end


end # class Arborist::MonitorRunner

