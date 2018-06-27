# -*- ruby -*-
# frozen_string_literal: true

require 'loggability'

require 'arborist/monitor' unless defined?( Arborist::Monitor )
require 'arborist/mixins'

using Arborist::TimeRefinements


# A mixin for adding batched connections for socket-based monitors.
module Arborist::Monitor::ConnectionBatching

	# The default number of connections to have open -- this should be well under
	# the RLIMIT_NOFILE of the current process.
	DEFAULT_BATCH_SIZE = 150

	# The default connection timeout
	DEFAULT_TIMEOUT = 2.0


	# An object that manages batching of connections and gathering results.
	class BatchRunner
		extend Loggability

		# Loggability API -- log to the Arborist logger
		log_to :arborist


		### Create a new BatchRunner for the specified +enum+ (an Enumerator)
		def initialize( enum, batch_size, timeout )
			@enum              = enum
			@results           = {}
			@current_batch     = []
			@connection_hashes = {}
			@start             = nil
			@batch_size        = batch_size || DEFAULT_BATCH_SIZE
			@timeout           = timeout || DEFAULT_TIMEOUT
		end


		######
		public
		######

		##
		# The Enumerator that yields connection hashes
		attr_accessor :enum

		##
		# The results hash
		attr_reader :results

		##
		# The batch of connection hashes that are currently being selected, ordered from
		# oldest to newest.
		attr_reader :current_batch

		##
		# An index of the current batch's connection hashes by connection.
		attr_reader :connection_hashes

		##
		# The Time the batch runner started.
		attr_accessor :start

		##
		# The maximum number of connections to have running at any time.
		attr_reader :batch_size

		##
		# The connection timeout from the monitor, in seconds
		attr_reader :timeout


		### Returns +true+ if the runner has been run and all connections have been
		### handled.
		def finished?
			return self.start && self.enum.nil? && self.current_batch.empty?
		end


		### Returns +true+ if the current batch is at capacity.
		def batch_full?
			return self.current_batch.length >= self.batch_size
		end


		### Fetch the next connection from the Enumerator, unsetting the enumerator and
		### returning +nil+ when it reaches the end.
		def next_connection
			conn_hash = self.enum.next
			conn_hash[:start] = Time.now
			conn_hash[:timeout_at] = conn_hash[:start] + self.timeout

			return conn_hash
		rescue StopIteration
			self.log.debug "Reached the end of the connections enum."
			self.enum = nil
			return nil
		end


		### Add a new conn_hash to the currrent batch. If the +conn_hash+'s connection
		### is an exception, don't add it and just add an error status for it built from
		### the exception.
		def add_connection( conn_hash )
			if conn_hash[:conn].is_a?( ::Exception )
				self.log.debug "Adding an error result for %{identifier}." % conn_hash
				self.results[ conn_hash[:identifier] ] = { error: conn_hash[:conn].message }
			else
				self.log.debug "Added connection for %{identifier} to the batch." % conn_hash
				self.current_batch.push( conn_hash )
				self.connection_hashes[ conn_hash[:conn] ] = conn_hash
			end
		end


		### Remove the specified +conn_hash+ from the current batch.
		def remove_connection( conn_hash )
			self.current_batch.delete( conn_hash )
			self.connection_hashes.delete( conn_hash[:conn] )
		end


		### Remove the connection hash for the specified +socket+ from the current
		### batch and return it (if it was in the batch).
		def remove_socket( socket )
			conn_hash = self.connection_hashes.delete( socket )
			self.current_batch.delete( conn_hash )

			return conn_hash
		end


		### Fill the #current_batch if it's not yet at capacity and there are more
		### connections to be made.
		def fill_batch
			# If the enum is not nil and the array isn't full, fetch a new connection
			while self.enum && !self.batch_full?
				self.log.debug "Adding connections to the queue."
				conn_hash = self.next_connection or break
				self.add_connection( conn_hash )
			end
		end


		### Shift any connections which have timed out off of the current batch and
		### return the timeout of the oldest non-timed-out connection.
		def remove_timedout_connections
			expired = self.current_batch.take_while do |conn_hash|
				conn_hash[ :timeout_at ].past?
			end

			wait_seconds = if self.current_batch.empty?
					1
				else
					self.current_batch.first[:timeout_at] - Time.now
				end

			expired.each do |conn_hash|
				self.remove_connection( conn_hash )
				self.log.debug "Discarding timed-out socket for %{identifier}." % conn_hash

				elapsed = conn_hash[:timeout_at] - conn_hash[:start]
				self.results[ conn_hash[:identifier] ] = {
					error: "Timeout after %0.3fs" % [ elapsed ]
				}
			end

			return wait_seconds.abs
		end


		### Wait at most +wait_seconds+ for one of the sockets in the current batch
		### to become ready. If any are ready before the +wait_seconds+ have elapsed,
		### returns them as an Array. If +wait_seconds+ goes by without any sockets becoming
		### ready, or if there were no sockets to wait on, returns +nil+.
		def wait_for_ready_connections( wait_seconds )
			sockets = self.connection_hashes.keys
			ready = nil

			self.log.debug "Selecting on %d sockets." % [ sockets.length ]
			_, ready, _ = IO.select( nil, sockets, nil, wait_seconds ) unless sockets.empty?

			return ready
		end


		### Run the batch runner, yielding to the specified +block+ as each connection
		### becomes ready.
		def run( &block )
			self.start = Time.now

			until self.finished?
				self.log.debug "Getting the status of %d connections." %
					[ self.current_batch.length ]

				self.fill_batch
				wait_seconds = self.remove_timedout_connections
				ready = self.wait_for_ready_connections( wait_seconds )

				# If the select returns ready sockets
				#   Build successful status for each ready socket
				now = Time.now
				ready.each do |sock|
					conn_hash = self.remove_socket( sock ) or
						raise "Ready socket %p was not in the current batch!" % [ sock ]

					identifier, start = conn_hash.values_at( :identifier, :start )
					duration = now - start

					results[ identifier ] = block.call( conn_hash, duration )
				end if ready
			end

			return Time.now - self.start
		end

	end # class BatchRunner


	### Inclusion callback -- add the #batchsize attribute to including monitors.
	def self::included( mod )
		mod.attr_accessor :timeout
		mod.attr_accessor :batch_size

		super
	end


	### Return a clone of the receiving monitor with its batch size set to
	### +new_size+.
	def with_batch_size( new_size )
		copy = self.clone
		copy.batch_size = new_size
		return copy
	end


	### Return a clone of receiving monitor with its timeout set to +new_timeout+.
	def with_timeout( new_timeout )
		copy = self.clone
		copy.timeout = new_timeout
		return copy
	end


	### Run the monitor, batching connections for the specified +nodes+ so the
	### monitor doesn't exhaust its file descriptors.
	def run( nodes )
		connections = self.make_connections_enum( nodes )
		return self.handle_connections( connections )
	end


	### Return an Enumerator that yields Hashes that describe the connections to be
	### made. They must contain, at a minimum, the following keys:
	###
	### +conn+:: The Socket (or other IO object) that is used to communicate with the
	###          monitored host. This should be created using non-blocking connection.
	### +identifier+:: The node identifier associated with the +conn+.
	###
	### You can add any other members to each Hash that you require to actually use
	### the connection when it becomes available.
	def make_connections_enum( nodes )
		raise "%p does not provide a %s method!" % [ __method__ ]
	end


	### Called when a socket becomes ready. It should generate a status update for
	### the node that corresponds to the given +node_hash+ and return it as a Hash.
	### The +duration+ is how long it took for the connection to be ready, in
	### seconds.
	def status_for_conn( conn_hash, duration )
		raise "%p does not provide a %s method!" % [ __method__ ]
	end


	### Fetch connections from +connections_enum+ and build a Hash of node updates
	### keyed by identifier based on the results.
	def handle_connections( connections_enum )
		runner = BatchRunner.new( connections_enum, self.batch_size, self.timeout )
		runner.run do |conn_hash, duration|
			self.status_for_conn( conn_hash, duration )
		end
		return runner.results
	end

end # module Arborist::Monitor::ConnectionBatching


