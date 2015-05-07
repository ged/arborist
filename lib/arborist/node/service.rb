# -*- ruby -*-
#encoding: utf-8

require 'etc'
require 'ipaddr'
require 'socket'

require 'arborist/node'


# A node type for Arborist trees that represent network-connected hosts.
class Arborist::Node::Service < Arborist::Node

	# The default transport layer protocol to use for services that don't specify
	# one
	DEFAULT_PROTOCOL = 'tcp'


	### Create a new Service node.
	def initialize( identifier, options={}, &block )
		@protocol = options[:protocol] || DEFAULT_PROTOCOL
		@port = options[:port] || default_port_for( identifier, @protocol )

		super
	end


	######
	public
	######

	##
	# The network port the service uses
	attr_reader :port

	##
	# The transport layer protocol the service uses
	attr_reader :protocol


	### Set an IP address of the host.
	def address( new_address, options={} )
		self.log.debug "Adding address %p to %p" % [ new_address, self ]
		case new_address
		when IPAddr
			@addresses << new_address
		when IPADDR_RE
			@addresses << IPAddr.new( new_address )
		when String
			ip_addr = TCPSocket.gethostbyname( new_address )
			@addresses << IPAddr.new( ip_addr[3] )
			@addresses << IPAddr.new( ip_addr[4] ) if ip_addr[4]
		else
			raise "I don't know how to parse a %p host address (%p)" %
				[ new_address.class, new_address ]
		end
	end


	#######
	private
	#######

	### Try to default the appropriate port based on the node's +identifier+
	### and +protocol+. Raises a SocketError if the service port can't be
	### looked up.
	def default_port_for( identifier, protocol )
		return Socket.getservbyname( identifier, protocol )
	end

end # class Arborist::Node::Service
