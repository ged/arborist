# -*- ruby -*-
#encoding: utf-8

require 'etc'
require 'ipaddr'
require 'socket'

require 'arborist/node'
require 'arborist/mixins'


# A node type for Arborist trees that represent services running on hosts.
class Arborist::Node::Service < Arborist::Node
	include Arborist::HashUtilities


	# The default transport layer protocol to use for services that don't specify
	# one
	DEFAULT_PROTOCOL = 'tcp'


	# Services live under Host nodes
	parent_type :host


	### Create a new Service node.
	def initialize( identifier, host, attributes={}, &block )
		raise Arborist::NodeError, "no host given" unless host.is_a?( Arborist::Node::Host )
		qualified_identifier = "%s-%s" % [ host.identifier, identifier ]

		@host = host

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

	### Set service +attributes+.
	def modify( attributes )
		attributes = stringify_keys( attributes )

		super

		self.port( attributes['port'] )
		self.app_protocol( attributes['app_protocol'] )
		self.protocol( attributes['protocol'] )
	end


	### Get/set the port the service is bound to.
	def port( new_port=nil )
		return @port unless new_port
		@port = new_port
	end


	### Get/set the (layer 7) protocol used by the service
	def app_protocol( new_proto=nil )
		return @app_protocol unless new_proto
		@app_protocol = new_proto
	end


	### Get/set the transport layer protocol the service uses
	def protocol( new_proto=nil )
		return @protocol unless new_proto
		@protocol = new_proto
	end


	### Delegate the service's address to its host.
	def addresses
		return @host.addresses
	end


	### Returns +true+ if the node matches the specified +key+ and +val+ criteria.
	def match_criteria?( key, val )
		self.log.debug "Matching %p: %p against %p" % [ key, val, self ]
		return case key
			when 'port'
				val = default_port_for( val, @protocol ) unless val.is_a?( Fixnum )
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
