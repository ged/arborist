# -*- ruby -*-
#encoding: utf-8

require 'time'
require 'loggability'
require 'timeout'
require 'socket'

require 'arborist/monitor' unless defined?( Arborist::Monitor )
require 'arborist/monitor/connection_batching'


# Socket-related Arborist monitor logic
module Arborist::Monitor::Socket
	extend Configurability


	configurability( 'arborist.monitors.socket' ) do

		##
		# The default timeout employed by the socket monitors, in floating-point
		# seconds.
		setting :default_timeout, default: 2.0 do |val|
			Float( val )
		end

		##
		# The number of socket connections to attempt simultaneously.
		setting :batch_size, default: 150 do |val|
			Integer( val )
		end
	end


	# Arborist TCP socket monitor logic
	class TCP
		extend Loggability
		include Arborist::Monitor::ConnectionBatching

		log_to :arborist


		# Always request the node addresses and port.
		USED_PROPERTIES = [ :addresses, :port ].freeze


		### Instantiate a monitor check and run it for the specified +nodes+.
		def self::run( nodes )
			return self.new.run( nodes )
		end


		### Return the properties used by this monitor.
		def self::node_properties
			return USED_PROPERTIES
		end


		### Create a new TCP monitor with the specified +options+. Valid options are:
		###
		### +:timeout+
		###   Set the number of seconds to wait for a connection for each node.
		### +:batch_size+
		###   The number of UDP connection attempts to perform simultaneously.
		def initialize( timeout: Arborist::Monitor::Socket.default_timeout, batch_size: Arborist::Monitor::Socket.batch_size )
			self.timeout = timeout
			self.batch_size = batch_size
		end


		######
		public
		######

		### Return an Enumerator that lazily yields Hashes of the form expected by the
		### ConnectionBatching mixin for each of the specified +nodes+.
		def make_connections_enum( nodes )
			return nodes.lazy.map do |identifier, node_data|
				self.log.debug "Creating a socket for %s" % [ identifier ]

				# :TODO: Should this try all the addresses? Should you be able to specify an
				# address for a Service?
				address = node_data['addresses'].first
				port = node_data['port']
				sockaddr = nil

				self.log.debug "Creating TCP connection for %s:%d" % [ address, port ]
				sock = Socket.new( :INET, :STREAM )

				conn = begin
						sockaddr = Socket.sockaddr_in( port, address )
						sock.connect_nonblock( sockaddr )
						sock
					rescue Errno::EINPROGRESS
						self.log.debug "  connection started"
						sock
					rescue => err
						self.log.error "  %p setting up connection: %s" % [ err.class, err.message ]
						err
					end

				{ conn: conn, identifier: identifier }
			end
		end


		### Build a status for the specified +conn_hash+ after its :conn has indicated
		### it is ready.
		def status_for_conn( conn_hash, duration )
			sock = conn_hash[:conn]
			# Why getpeername? Testing socket success without read()ing, I think?
			# FreeBSD source?
			res = sock.getpeername
			return {
				tcp_socket_connect: { duration: duration }
			}
		rescue SocketError, SystemCallError => err
			self.log.debug "Got %p while connecting to %s" % [ err.class, conn_hash[:identifier] ]
			begin
				sock.read( 1 )
			rescue => err
				return { error: err.message }
			end
		ensure
			sock.close if sock
		end

	end # class TCP


	# Arborist UDP socket monitor logic
	class UDP
		extend Loggability
		include Arborist::Monitor::ConnectionBatching

		log_to :arborist

		# Always request the node addresses and port.
		USED_PROPERTIES = [ :addresses, :port ].freeze


		### Instantiate a monitor check and run it for the specified +nodes+.
		def self::run( nodes )
			return self.new.run( nodes )
		end


		### Return the properties used by this monitor.
		def self::node_properties
			return USED_PROPERTIES
		end


		### Create a new UDP monitor with the specified +options+. Valid options are:
		###
		### +:timeout+
		###   Set the number of seconds to wait for a connection for each node.
		### +:batch_size+
		###   The number of UDP connection attempts to perform simultaneously.
		def initialize( timeout: Arborist::Monitor::Socket.default_timeout, batch_size: Arborist::Monitor::Socket.batch_size )
			self.timeout = timeout
			self.batch_size = batch_size
		end


		######
		public
		######

		### Open a socket for each of the specified nodes and return a Hash of
		### the sockets (or the error from the connection attempt) keyed by
		### node identifier.
		def make_connections_enum( nodes )
			return nodes.lazy.map do |identifier, node_data|
				address = node_data['addresses'].first
				port = node_data['port']

				self.log.debug "Creating UDP connection for %s:%d" % [ address, port ]
				sock = Socket.new( :INET, :DGRAM )

				conn = begin
						sockaddr = Socket.sockaddr_in( port, address )
						sock.connect( sockaddr )
						sock.send( '', 0 )
						sock.recvfrom_nonblock( 1 )
						sock
					rescue Errno::EAGAIN
						self.log.debug "  connection started"
						sock
					rescue => err
						self.log.error "  %p setting up connection: %s" % [ err.class, err.message ]
						err
					end

				self.log.debug "UDP connection object is: %p" % [ conn ]
				{ conn: conn, identifier: identifier }
			end
		end


		### Build a status for the specified +conn_hash+ after its :conn has indicated
		### it is ready.
		def status_for_conn( conn_hash, duration )
			sock = conn_hash[:conn]
			sock.recvfrom_nonblock( 1 )
			return {
				udp_socket_connect: { duration: duration }
			}
		rescue Errno::EAGAIN
			return {
				udp_socket_connect: { duration: duration }
			}
		rescue SocketError, SystemCallError => err
			self.log.debug "Got %p while connecting to %s" % [ err.class, conn_hash[:identifier] ]
			return { error: err.message }
		ensure
			sock.close if sock
		end


	end # class UDP


end # module Arborist::Monitor::Socket


