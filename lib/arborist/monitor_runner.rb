# -*- ruby -*-
#encoding: utf-8

require 'set'

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

	# Number of seconds between thread cleanup
	THREAD_CLEANUP_INTERVAL = 5 # seconds


	log_to :arborist


	### Create a new Arborist::MonitorRunner
	def initialize
		@monitors        = []
		@handler         = nil
		@reactor         = CZTop::Reactor.new
		@client          = Arborist::Client.new
		@runner_threads  = {}
		@request_queue   = {}
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

	##
	# A hash of monitor object -> thread used to contain and track running monitor threads.
	attr_reader :runner_threads


	### Load monitors from the specified +enumerator+.
	def load_monitors( enumerator )
		self.monitors.concat( enumerator.to_a )
	end


	### Run the specified +monitors+
	def run
		self.monitors.each do |mon|
			self.add_timer_for( mon )
		end

		self.add_thread_cleanup_timer

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


	### Update nodes with the results of a monitor's run.
	def run_monitor( monitor )
		positive     = monitor.positive_criteria
		negative     = monitor.negative_criteria
		exclude_down = monitor.exclude_down?
		props        = monitor.node_properties

		self.search( positive, exclude_down, props, negative ) do |nodes|
			self.log.info "Running %p monitor for %d node(s)" % [
				monitor.description,
				nodes.length
			]

			unless nodes.empty?
				self.runner_threads[ monitor ] = Thread.new do
					Thread.current[:monitor_desc] = monitor.description
					results = self.run_monitor_safely( monitor, nodes )

					self.log.debug "  updating with results: %p" % [ results ]
					self.update( results ) do
						self.log.debug "Updated %d via the '%s' monitor" %
							[ results.length, monitor.description ]
					end
				end
				self.log.debug "THREAD: Started %p for %p" % [ self.runner_threads[monitor], monitor ]
				self.log.debug "THREAD: Runner threads have: %p" % [ self.runner_threads.to_a ]
			end
		end
	end


	### Exec +monitor+ against the provided +nodes+ hash, treating
	### runtime exceptions as an error condition.  Returns an update
	### hash, keyed by node identifier.
	###
	def run_monitor_safely( monitor, nodes )
		results = begin
			monitor.run( nodes )
		rescue => err
			errmsg = "Exception while running %p monitor: %s: %s" % [
				monitor.description,
				err.class.name,
				err.message
			]
			self.log.error "%s\n%s" % [ errmsg, err.backtrace.join("\n  ") ]
			nodes.keys.each_with_object({}) do |id, results|
				results[id] = { error: errmsg }
			end
		end

		return results
	end


	### Create a search request using the runner's client, then queue the request up
	### with the specified +block+ as the callback.
	def search( criteria, exclude_down, properties, negative={}, &block )
		search = self.client.make_search_request( criteria,
			exclude_down: exclude_down,
			properties: properties,
			exclude: negative
		)
		self.queue_request( search, &block )
	end


	### Create an update request using the runner's client, then queue the request up
	### with the specified +block+ as the callback.
	def update( nodemap, &block )
		return if nodemap.empty?
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
			unless self.runner_threads.key?( monitor )
				self.run_monitor( monitor )
			end
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


	### Set up a timer to clean up monitor threads.
	def add_thread_cleanup_timer
		self.log.debug "Starting thread cleanup timer for %p." % [ self.runner_threads ]
		self.reactor.add_periodic_timer( THREAD_CLEANUP_INTERVAL ) do
			self.cleanup_monitor_threads
		end
	end


	### :TODO: Handle the thread-interrupt stuff?

	### Clean up any monitor runner threads that are dead.
	def cleanup_monitor_threads
		self.runner_threads.values.reject( &:alive? ).each do |thr|
			monitor = self.runner_threads.key( thr )
			self.runner_threads.delete( monitor )

			begin
				thr.join
			rescue => err
				self.log.error "%p while running %s: %s" %
					[ err.class, thr[:monitor_desc], err.message ]
			end
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

