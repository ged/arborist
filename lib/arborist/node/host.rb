# -*- ruby -*-
#encoding: utf-8

require 'etc'
require 'ipaddr'

require 'arborist/node'


# A node type for Arborist trees that represent network-connected hosts.
#
#    host_node = Arborist::Node.create( :host, 'acme' ) do
#        description "Public-facing webserver"
#        address '93.184.216.34'
#
#        tags :public, :dmz
#        
#        resource 'disk'
#        resource 'memory' do
#            config hwm: '3.4G'
#        end
#        resource 'loadavg'
#        resource 'processes' do
#            config expect: { nginx: 2 }
#        end
#        
#        service 'ssh'
#        service 'www'
#
#    end
#
#
class Arborist::Node::Host < Arborist::Node

	# A union of IPv4 and IPv6 regular expressions.
	IPADDR_RE = Regexp.union(
		IPAddr::RE_IPV4ADDRLIKE,
		IPAddr::RE_IPV6ADDRLIKE_COMPRESSED,
		IPAddr::RE_IPV6ADDRLIKE_FULL
	)


	### Create a new Host node.
	def initialize( identifier, attributes={}, &block )
		@addresses = []
		super
	end


	######
	public
	######

	##
	# The network address(es) of this Host as an Array of IPAddr objects
	attr_reader :addresses


	### Set one or more node +attributes+. Supported attributes (in addition to
	### those supported by Node) are: +addresses+.
	def modify( attributes )
		attributes = stringify_keys( attributes )

		super

		if attributes['addresses']
			self.addresses.clear
			Array( attributes['addresses'] ).each do |addr|
				self.address( addr )
			end
		end
	end


	### Return the host's operational attributes.
	def operational_values
		properties = super
		return properties.merge( addresses: self.addresses.map(&:to_s) )
	end


	### Set an IP address of the host.
	def address( new_address )
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


	### Return host-node-specific information for #inspect.
	def node_description
		return "{no addresses}" if self.addresses.empty?
		return "{addresses: %s}" % [ self.addresses.map(&:to_s).join(', ') ]
	end


	#
	# Serialization
	#

	### Return a Hash of the host node's state.
	def to_h
		return super.merge( addresses: self.addresses.map(&:to_s) )
	end


	### Marshal API -- set up the object's state using the +hash+ from a previously-marshalled
	### node. Overridden to turn the addresses back into IPAddr objects.
	def marshal_load( hash )
		super
		@addresses = hash[:addresses].map {|addr| IPAddr.new(addr) }
	end


	### Equality operator -- returns +true+ if +other_node+ is equal to the
	### receiver. Overridden to also compare addresses.
	def ==( other_host )
		return super && other_host.addresses == self.addresses
	end

end # class Arborist::Node::Host
