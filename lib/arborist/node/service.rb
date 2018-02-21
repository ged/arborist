# -*- ruby -*-
#encoding: utf-8

require 'etc'
require 'ipaddr'
require 'socket'

require 'arborist/node'
require 'arborist/mixins'
require 'arborist/exceptions'


# A node type for Arborist trees that represent services running on hosts.
class Arborist::Node::Service < Arborist::Node
	include Arborist::HashUtilities,
	        Arborist::NetworkUtilities


	# The default transport layer protocol to use for services that don't specify
	# one
	DEFAULT_PROTOCOL = 'tcp'


	# Services live under Host nodes
	parent_type :host


	### Create a new Service node.
	def initialize( identifier, host, attributes={}, &block )
		raise Arborist::NodeError, "no host given" unless host.is_a?( Arborist::Node::Host )
		qualified_identifier = "%s-%s" % [ host.identifier, identifier ]

		@host         = host
		@addresses    = nil
		@app_protocol = nil
		@protocol     = nil
		@port         = nil

		attributes[ :app_protocol ] ||= identifier
		attributes[ :protocol ] ||= DEFAULT_PROTOCOL

		super( qualified_identifier, host, attributes, &block )

		unless @port
			service_port = default_port_for( @app_protocol, @protocol ) or
				raise ArgumentError, "can't determine the port for %s/%s" %
					[ @app_protocol, @protocol ]
			@port = Integer( service_port )
		end
	end


	######
	public
	######

	##
	# Get/set the port the service binds to
	dsl_accessor :port

	##
	# Get/set the application protocol the service uses
	dsl_accessor :app_protocol

	##
	# Get/set the network protocol the service uses
	dsl_accessor :protocol


	### Set service +attributes+.
	def modify( attributes )
		attributes = stringify_keys( attributes )

		super

		self.port( attributes['port'] )
		self.app_protocol( attributes['app_protocol'] )
		self.protocol( attributes['protocol'] )
	end


	### Set an IP address of the service. This must be one of the addresses of its
	### containing host.
	def address( new_address )
		self.log.debug "Adding address %p to %p" % [ new_address, self ]
		normalized_addresses = normalize_address( new_address )

		unless normalized_addresses.all? {|addr| @host.addresses.include?(addr) }
			raise Arborist::ConfigError, "%s is not one of %s's addresses" %
				[ new_address, @host.identifier ]
		end

		@addresses ||= []
		@addresses += normalized_addresses
	end


	### Delegate the service's address to its host.
	def addresses
		return @addresses || @host.addresses
	end


	### Delegate the service's hostname to it's parent host.
	def hostname
		return @host.hostname
	end


	### Returns +true+ if the node matches the specified +key+ and +val+ criteria.
	def match_criteria?( key, val )
		self.log.debug "Matching %p: %p against %p" % [ key, val, self ]
		return case key
			when 'port'
				val = default_port_for( val, @protocol ) unless val.is_a?( Integer )
				self.port == val.to_i
			when 'address'
				search_addr = IPAddr.new( val )
				self.addresses.any? {|a| search_addr.include?(a) }
			when 'protocol' then self.protocol == val.downcase
			when 'app', 'app_protocol' then self.app_protocol == val
			else
				super
			end
	end


	### Return a Hash of the operational values that are included with the node's
	### monitor state.
	def operational_values
		return super.merge(
			addresses: self.addresses.map( &:to_s ),
			port: self.port,
			protocol: self.protocol,
			app_protocol: self.app_protocol,
		)
	end


	### Return service-node-specific information for #inspect.
	def node_description
		return "{listening on %s port %d}" % [
			self.protocol,
			self.port,
		]
	end


	### Overridden to disallow modification of a Service's parent, as it needs a reference to
	### the Host node for delegation.
	def parent( new_parent=nil )
		return super unless new_parent
		raise "Can't reparent a service; replace the node instead"
	end


	#
	# Serialization
	#

	### Return a Hash of the host node's state.
	def to_h( * )
		return super.merge(
			addresses: self.addresses.map(&:to_s),
			protocol: self.protocol,
			app_protocol: self.app_protocol,
			port: self.port
		)
	end


	### Equality operator -- returns +true+ if +other_node+ is equal to the
	### receiver. Overridden to also compare addresses.
	def ==( other_host )
		return super &&
			other_host.addresses == self.addresses &&
			other_host.protocol == self.protocol &&
			other_host.app_protocol == self.app_protocol &&
			other_host.port == self.port
	end


	#######
	private
	#######

	### Try to default the appropriate port based on the node's +identifier+
	### and +protocol+. Raises a SocketError if the service port can't be
	### looked up.
	def default_port_for( identifier, protocol )
		return Socket.getservbyname( identifier, protocol )
	rescue SocketError
		return nil
	end

end # class Arborist::Node::Service
