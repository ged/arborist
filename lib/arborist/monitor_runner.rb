# -*- ruby -*-
#encoding: utf-8

require 'rbczmq'
require 'loggability'

require 'arborist' unless defined?( Arborist )
require 'arborist/client'


# Undo the useless scoping
class ZMQ::Loop
	public_class_method :instance
end


# An event-driven runner for Arborist::Monitors.
class Arborist::MonitorRunner
	extend Loggability

	log_to :arborist


	# A ZMQ::Handler object for managing IO for all running monitors.
	class Handler < ZMQ::Handler
		extend Loggability,
		       Arborist::MethodUtilities

		log_to :arborist

		### Create a ZMQ::Handler that acts as the agent that runs the specified
		### +monitor+.
		def initialize( reactor )
			@reactor = reactor
			@client = Arborist::Client.new
			@pollitem = ZMQ::Pollitem.new( @client.tree_api, ZMQ::POLLOUT )
			@pollitem.handler = self

			@request_queue = {}
			@registered = false
		end


		######
		public
		######

		# The ZMQ::Loop that this runner is registered with
		attr_reader :reactor

		# The Queue of pending requests, keyed by the callback that should be called with the
		# results.
		attr_reader :request_queue

		# The Arborist::Client that will provide the message packing and unpacking
		attr_reader :client

		##
		# True if the Handler is registered to write one or more requests
		attr_predicate :registered


		### Run the specified +monitor+ and update nodes with the results.
		def run_monitor( monitor )
			positive     = monitor.positive_criteria
			negative     = monitor.negative_criteria
			include_down = monitor.include_down?
			props        = monitor.node_properties

			self.fetch( positive, include_down, props, negative ) do |nodes|
				results = monitor.run( nodes )
				monitor_key = monitor.key

				results.each do |ident, properties|
					properties['_monitor_key'] = monitor_key
				end

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


		### Register the handler's pollitem as being ready to write if it isn't already.
		def register
			# self.log.debug "Registering for writing."
			self.reactor.register( self.pollitem ) unless @registered
			@registered = true
		end


		### Unregister the handler's pollitem from the reactor when there's nothing ready
		### to write.
		def unregister
			# self.log.debug "Unregistering for writing."
			self.reactor.remove( self.pollitem ) if @registered
			@registered = false
		end


		### Write commands from the queue
		def on_writable
			if (( pair = self.request_queue.shift ))
				callback, request = *pair
				res = self.client.send_tree_api_request( request )
				callback.call( res )
			end

			self.unregister if self.request_queue.empty?
			return true
		end

	end # class Handler


	### Create a new Arborist::MonitorRunner
	def initialize
		@monitors = []
		@handler = nil
		@reactor = ZMQ::Loop.new
	end


	######
	public
	######

	# The Array of loaded Arborist::Monitors the runner should run.
	attr_reader :monitors

	# The ZMQ::Handler subclass that handles all async IO
	attr_accessor :handler

	# The reactor (a ZMQ::Loop) the runner uses to drive everything
	attr_accessor :reactor


	### Load monitors from the specified +enumerator+.
	def load_monitors( enumerator )
		@monitors += enumerator.to_a
	end


	### Run the specified +monitors+
	def run
		self.handler = Arborist::MonitorRunner::Handler.new( self.reactor )

		self.monitors.each do |mon|
			self.add_timer_for( mon )
		end

		self.reactor.start
	end


	### Register a timer for the specified +monitor+.
	def add_timer_for( monitor )
		interval = monitor.interval

		timer = if monitor.splay.nonzero?
				self.splay_timer_for( monitor )
			else
				self.interval_timer_for( monitor )
			end

		self.reactor.register_timer( timer )
	end


	### Create a repeating ZMQ::Timer that will run the specified monitor on its interval.
	def interval_timer_for( monitor )
		interval = monitor.interval
		self.log.info "Creating timer for %p" % [ monitor ]

		return ZMQ::Timer.new( interval, 0 ) do
			self.handler.run_monitor( monitor )
		end
	end


	### Create a one-shot ZMQ::Timer that will register the interval timer for the specified
	### +monitor+ after a random number of seconds no greater than its splay.
	def splay_timer_for( monitor )
		delay = rand( monitor.splay )
		self.log.debug "Splaying registration of %p for %ds" % [ monitor, delay ]

		return ZMQ::Timer.new( delay, 1 ) do
			interval_timer = self.interval_timer_for( monitor )
			self.reactor.register_timer( interval_timer )
		end
	end

end # class Arborist::MonitorRunner

