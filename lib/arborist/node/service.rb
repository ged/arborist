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
		super( my_identifier, options )

		@type = options[:type] || identifier
		@protocol = options[:protocol] || DEFAULT_PROTOCOL
		@port = options[:port] || default_port_for( @type, @protocol )
		@parent = host.identifier

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
	# The type of service (layer 7 protocol)
	attr_reader :type


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
