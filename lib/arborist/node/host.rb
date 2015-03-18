# -*- ruby -*-
#encoding: utf-8

require 'etc'
require 'ipaddr'

require 'arborist/node'


# A node type for Arborist trees that represent network-connected hosts.
class Arborist::Node::Host < Arborist::Node


	### Create a new Host node.
	def initialize( identifier, options={}, &block )
		@addresses = []
		@services  = []

		super
	end


	######
	public
	######

	##
	# The network address(es) of this Host as an Array of IPAddr objects
	attr_reader :addresses

	##
	# The services running on the Host, as an Array of
	attr_reader :services


	### Set an IP address of the host.
	def address( new_address, options={} )
		new_address = IPAddr.new( new_address ) unless new_address.is_a?( IPAddr )
		@addresses << new_address
	end


	### Add a service to the host
	def service( name, options={} )
		parent_id = self.identifier
		Arborist::Node.create( :service, name, options ) do
			parent( parent_id )
		end
	end


	### Add a web service to the host.
	def webservice( name, options={} )

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
