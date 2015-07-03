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
	def initialize( identifier, &block )
		@addresses = []
		super
	end


	######
	public
	######

	##
	# The network address(es) of this Host as an Array of IPAddr objects
	attr_reader :addresses


	### Return the host's operational attributes.
	def operational_values
		properties = super
		return properties.merge( addresses: self.addresses.map(&:to_s) )
	end


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


	### Returns +true+ if the node matches the specified +key+ and +val+ criteria.
	def match_criteria?( key, val )
		return case key
			when 'address'
				search_addr = IPAddr.new( val )
				@addresses.any? {|a| search_addr.include?(a) }
			else
				super
			end
	end


	### Add a service to the host
	def service( name, options={}, &block )
		return Arborist::Node.create( :service, name, self, options, &block )
	end


end # class Arborist::Node::Host
