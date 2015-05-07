# -*- ruby -*-
#encoding: utf-8

require 'etc'
require 'ipaddr'

require 'arborist/node'


# A node type for Arborist trees that represent network-connected hosts.
class Arborist::Node::Host < Arborist::Node

	# A union of IPv4 and IPv6 regular expressions.
	IPADDR_RE = Regexp.union(
		IPAddr::RE_IPV4ADDRLIKE,
		IPAddr::RE_IPV6ADDRLIKE_COMPRESSED,
		IPAddr::RE_IPV6ADDRLIKE_FULL
	)


	### Create a new Host node.
	def initialize( identifier, options={}, &block )
		@addresses = []
		super
	end


	######
	public
	######

	##
	# The network address(es) of this Host as an Array of IPAddr objects
	attr_reader :addresses

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


end # class Arborist::Node::Host
