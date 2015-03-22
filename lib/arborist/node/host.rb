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
		new_address = case new_address
			when IPADDR_RE
				IPAddr.new( new_address ) unless new_address.is_a?( IPAddr )
			when String
				ip_addr = Socket.gethostbyname( new_address )
				ip_addr[2]
			else
				raise "I don't know how to parse a %p host address (%p)" %
					[ new_address.class, new_address ]
			end
		@addresses << new_address
	end


	### Add a service to the host
	def service( name, options={} )
		parent_id = self.identifier
		name = "%s-%s" % [ parent_id, name ]
		self.subnodes << Arborist::Node.create( :service, name, options ) do
			parent( parent_id )
		end
	end


	### Add a web service to the host.
	def webservice( name='www', options={} )
		parent_id = self.identifier
		name = "%s-webservice-%s" % [ parent_id, name ]
		self.subnodes << Arborist::Node.create( :service, name, options ) do
			parent( parent_id )
		end
	end


	#########
	protected
	#########

	### Look up the port corresponding to +service_name+ and return it
	### if the lookup succeeds. Returns +nil+ if no such service port
	### is known.
	def lookup_service_port( service_name )
		return Socket.getservbyname( service_name )
	rescue SocketError
		return nil
	end

end # class Arborist::Node::Host
