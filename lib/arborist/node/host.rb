# -*- ruby -*-
#encoding: utf-8

require 'etc'

require 'arborist/node'
require 'arborist/mixins'


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
	include Arborist::NetworkUtilities

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

	##
	# An optional hostname.
	dsl_accessor :hostname


	### Set one or more node +attributes+. Supported attributes (in addition to
	### those supported by Node) are: +addresses+.
	def modify( attributes )
		attributes = stringify_keys( attributes )

		super

		self.hostname( attributes['hostname'] ) if attributes[ 'hostname' ]
		if attributes[ 'addresses' ]
			self.addresses.clear
			Array( attributes['addresses'] ).each do |addr|
				self.address( addr )
			end
		end
	end


	### Return the host's operational attributes.
	def operational_values
		properties = super
		return properties.merge(
			hostname: @hostname,
			addresses: self.addresses.map(&:to_s)
		)
	end


	### Set an IP address of the host.
	def address( new_address )
		self.log.debug "Adding address %p to %p" % [ new_address, self ]

		if new_address =~ /^[[:alnum:]][a-z0-9\-]+/i && ! @hostname
			@hostname = new_address
		end

		@addresses += normalize_address( new_address )
		@addresses.uniq!
	end


	### Returns +true+ if the node matches the specified +key+ and +val+ criteria.
	def match_criteria?( key, val )
		return case key
			when 'hostname' then @hostname == val
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
	def to_h( * )
		return super.merge(
			hostname:  @hostname,
			addresses: self.addresses.map(&:to_s)
		)
	end


	### Marshal API -- set up the object's state using the +hash+ from a previously-marshalled
	### node. Overridden to turn the addresses back into IPAddr objects.
	def marshal_load( hash )
		super
		@addresses = hash[:addresses].map {|addr| IPAddr.new(addr) }
		@hostname = hash[:hostname]
	end


	### Equality operator -- returns +true+ if +other_node+ is equal to the
	### receiver. Overridden to also compare addresses.
	def ==( other_host )
		return super &&
			other_host.addresses == self.addresses &&
			other_host.hostname == @hostname
	end

end # class Arborist::Node::Host
