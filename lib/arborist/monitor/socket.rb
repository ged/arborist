# -*- ruby -*-
#encoding: utf-8

require 'loggability'
require 'timeout'

require 'arborist/monitor' unless defined?( Arborist::Monitor )

using Arborist::TimeRefinements


# Socket-related Arborist monitor logic
module Arborist::Monitor::Socket


	# Arborist TCP socket monitor logic
	class TCP
		extend Loggability
		log_to :arborist


		# Defaults for instances of this monitor
		DEFAULT_OPTIONS = {
			timeout: 2.seconds
		}


		### Instantiate a monitor check and run it for the specified +nodes+.
		def self::run( nodes )
			return self.new.run( nodes )
		end


		### Create a new TCP monitor with the specified +options+. Valid options are:
		###
		### +:timeout+
		###   Set the number of seconds to wait for a connection for each node.
		def initialize( options=DEFAULT_OPTIONS )
			options = DEFAULT_OPTIONS.merge( options || {} )

			options.each do |name, value|
				self.public_send( "#{name}=", value )
			end
		end


		######
		public
		######

		# The timeout for connecting, in seconds.
		attr_accessor :timeout


		### Run the TCP check for each of the specified Hash of +nodes+ and return a Hash of
		### updates for them based on trying to connect to them.
		def run( nodes )
			self.log.debug "Got nodes to TCP check: %p" % [ nodes ]

			connections = self.make_connections( nodes )
			return self.wait_for_connections( connections )
		end


		### Return a clone of this object with its timeout set to +new_timeout+.
		def with_timeout( new_timeout )
			copy = self.clone
			copy.timeout = new_timeout
			return copy
		end


		### Open a socket for each of the specified nodes using non-blocking connect(2), and
		### return a Hash of the sockets (or the error from the connection attempt) keyed by
		### node identifier.
		def make_connections( nodes )
			return nodes.each_with_object( {} ) do |(identifier, node_data), accum|

				# :TODO: Should this try all the addresses? Should you be able to specify an
				# address for a Service?
				address = node_data['addresses'].first
				port = node_data['port']

				self.log.debug "Creating TCP connection for %s:%d" % [ address, port ]
				sock = Socket.new( :INET, :STREAM )

				conn = begin
						sockaddr = Socket.sockaddr_in( port, address )
						sock.connect_nonblock( sockaddr )
					rescue Errno::EINPROGRESS
						self.log.debug "  connection started"
						sock
					rescue => err
						self.log.error "  %p setting up connection: %s" % [ err.class, err.message ]
						err
					end

				accum[ identifier ] = conn
			end
		end


		### For any elements of +connections+ that are sockets, wait on them to complete or error
		### and then return a Hash of node updates keyed by identifier based on the results.
		def wait_for_connections( connections )
			results = {}
			start = Time.now
			timeout_at = Time.now + self.timeout

			# First strip out all the ones that failed in the first #connect_nonblock
			connections.delete_if do |identifier, sock|
				next false if sock.respond_to?( :connect_nonblock ) # Keep sockets
				self.log.debug "  removing connect error for node %s" % [ identifier ]
				results[ identifier ] = { error: sock.message }
			end

			# Now wait for connections to complete
			until connections.empty? || timeout_at.past?
				self.log.debug "Waiting on %d connections for %0.3ds..." %
					[ connections.values.length, timeout_at - Time.now ]
				_, ready, _ = IO.select( nil, connections.values, nil, timeout_at - Time.now )

				self.log.debug "  select returned: %p" % [ ready ]
				ready.each do |sock|
					self.log.debug "  %p is ready" % [ sock ]
					identifier = connections.key( sock )
					connections.delete( identifier )
					self.log.debug "%p became writable: testing connection state" % [ sock ]

					begin
						self.log.debug "  trying another connection to %p" % [ sock.remote_address.to_sockaddr ]
						sock.connect_nonblock( sock.remote_address.to_sockaddr )
					rescue Errno::EISCONN
						self.log.debug "  connection successful"
						results[ identifier ] = {
							tcp_socket_connect: { time: Time.now, duration: Time.now - start }
						}
					rescue SocketError, Errno => err
						self.log.debug "%p during connection: %s" % [ err.class, err.message ]
						results[ identifier ] = { error: result.message }
					ensure
						sock.close
					end
				end if ready

			end

			# Anything left is a timeout
			connections.each do |identifier, sock|
				self.log.debug "%s: timeout (no connection in %0.3ds)" % [ identifier, self.timeout ]
				results[ identifier ] = { error: "Timeout after %0.3fs" % [self.timeout] }
				sock.close
			end

			return results
		end

	end # class TCP


end # module Arborist::Monitor::Socket


