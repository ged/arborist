#!/usr/bin/env ruby

require 'rbczmq'
require 'loggability'

require 'arborist'
require 'arborist/client'


class MonitorRunner < ZMQ::Handler
	extend Loggability

	log_to :arborist


	### Create a ZMQ::Handler that acts as the agent that runs the specified
	### +monitor+.
	def initialize( pollitem, reactor, client )
		super
		@reactor       = reactor
		@client        = client
		@request_queue = {}
		@registered    = false
	end


	# The ZMQ::Loop that this runner is registered with
	attr_reader :reactor

	# The Queue of pending requests, keyed by the callback that should be called with the
	# results.
	attr_reader :request_queue

	# The Arborist::Client that will provide the message packing and unpacking
	attr_reader :client


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


	### Create a fetch request using the runner's client, then queue the request up
	### with the specified +block+ as the callback.
	def fetch( criteria, include_down, properties, &block )
		fetch = self.client.make_fetch_request( criteria,
			include_down: include_down,
			properties: properties
		)
		self.queue_request( fetch, &block )
	end


	### Create an update request using the runner's client, then queue the request up
	### with the specified +block+ as the callback.
	def update( nodemap, &block )
		update = self.client.make_update_request( nodemap )
		self.queue_request( update, &block )
	end


	### Run the specified +monitor+ and update nodes with the results.
	def run_monitor( monitor )
		self.fetch( monitor.positive_criteria, monitor.include_down?, monitor.node_properties ) do |nodes|
			# :FIXME: Doesn't apply negative criteria
			results = monitor.run( nodes )
			self.update( results ) do
				self.log.debug "Updated %d via the '%s' monitor" %
					[ results.length, monitor.description ]
			end
		end
	end

end # class MonitorRunner


# Undo the useless scoping
class ZMQ::Loop
	public_class_method :instance
end


monitors_path = ARGV.shift or raise "No monitor file specified."
Arborist.load_config( ARGV.shift )
Arborist.load_all

monitors = Arborist::Monitor.each_in( monitors_path )
client = Arborist::Client.new

ZMQ::Loop.run do
	pollitem = ZMQ::Loop.register_writable( client.make_tree_api_socket,
		MonitorRunner,
		ZMQ::Loop.instance,
		client )

	monitors.each do |mon|
		ZMQ::Loop.add_periodic_timer( mon.interval ) do
			# :FIXME: No skew
			pollitem.handler.run_monitor( mon )
		end
	end
end