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
	def initialize( identifier, host, options={}, &block )
		my_identifier = "%s-%s" % [ host.identifier, identifier ]
		super( my_identifier )

		@host = host
		@parent = host.identifier
		@app_protocol = options[:app_protocol] || identifier
		@protocol = options[:protocol] || DEFAULT_PROTOCOL
		@port = Integer( options[:port] || default_port_for(@app_protocol, @protocol) )

		self.instance_eval( &block ) if block
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

	##
	# The (layer 7) protocol used by the service
	attr_reader :app_protocol


	### Delegate the service's address to its host.
	def addresses
		return @host.addresses
	end


	### Returns +true+ if the node matches the specified +key+ and +val+ criteria.
	def match_criteria?( key, val )
		return case key
			when 'port' then self.port == val.to_i
			when 'address' then self.addresses.include?( val )
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
