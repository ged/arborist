# -*- ruby -*-
#encoding: utf-8

require 'arborist' unless defined?( Arborist )
require 'msgpack'


# Unified Arborist Manager client for both the Tree and Event APIs
class Arborist::Client
	extend Loggability

	# The version of the client.
	API_VERSION = 1

	# Loggability API -- log to the Arborist log host
	log_to :arborist


	### Create a new Client with the given API socket URIs.
	def initialize( tree_api_url: nil, event_api_url: nil )
		@tree_api_url  = tree_api_url  || Arborist.tree_api_url
		@event_api_url = event_api_url || Arborist.event_api_url

		@request_queue = nil
		@event_subscriptions = nil
	end


	######
	public
	######

	# The ZMQ URI required to speak to the Arborist tree API.
	attr_accessor :tree_api_url

	# The ZMQ URI required to speak to the Arborist event API.
	attr_accessor :event_api_url


	### Return the manager's current status as a hash.
	def status
		request = self.make_status_request
		return self.send_tree_api_request( request )
	end


	### Return the manager's current status as a hash.
	def make_status_request
		return self.pack_message( :status )
	end


	### Return the manager's current node tree.
	def list( *args )
		request = self.make_list_request( *args )
		return self.send_tree_api_request( request )
	end


	### Return the manager's current node tree.
	def make_list_request( from: nil )
		header = {}
		self.log.debug "From is: %p" % [ from ]
		header[:from] = from if from

		return self.pack_message( :list, header )
	end


	### Return the manager's current node tree.
	def fetch( criteria={}, *args )
		request = self.make_fetch_request( criteria, *args )
		return self.send_tree_api_request( request )
	end


	### Return the manager's current node tree.
	def make_fetch_request( criteria, include_down: false, properties: :all )
		header = {}
		header[ :include_down ] = true if include_down
		header[ :return ] = properties if properties != :all

		return self.pack_message( :fetch, header, criteria )
	end


	### Update the identified nodes in the manager with the specified data.
	def update( *args )
		request = self.make_update_request( *args )
		return self.send_tree_api_request( request )
	end


	### Update the identified nodes in the manager with the specified data.
	def make_update_request( data )
		return self.pack_message( :update, nil, data )
	end


	### Send the packed +request+ via the Tree API socket, raise an error on
	### unsuccessful response, and return the response body.
	def send_tree_api_request( request )
		self.log.debug "Sending request: %p" % [ request ]
		self.tree_api.send( request )

		res = self.tree_api.recv
		self.log.debug "Received response: %p" % [ res ]

		header, body = self.unpack_message( res )
		unless header[ 'success' ]
			raise "Arborist manager said: %s" % [ header['reason'] ]
		end

		return body
	end



	### Format ruby +data+ for communicating with the Arborist manager.
	def pack_message( verb, *data )
		header = data.shift || {}
		body   = data.shift

		header.merge!( action: verb, version: API_VERSION )

		self.log.debug "Packing message; header: %p, body: %p" % [ header, body ]

		return MessagePack.pack([ header, body ])
	end


	### De-serialize an Arborist manager response.
	def unpack_message( msg )
		return MessagePack.unpack( msg )
	end


	### Return a ZMQ REQ socket connected to the manager's tree API, instantiating
	### it if necessary.
	def tree_api
		return @tree_api ||= self.make_tree_api_socket
	end


	### Create a new ZMQ REQ socket connected to the manager's tree API.
	def make_tree_api_socket
		self.log.info "Connecting to the tree socket %p" % [ self.tree_api_url ]
		sock = Arborist.zmq_context.socket( :REQ )
		sock.connect( self.tree_api_url )

		return sock
	end


	### Return a ZMQ SUB socket connected to the manager's event API, instantiating
	### it if necessary.
	def event_api
		return @event_api ||= self.make_event_api_socket
	end


	### Create a new ZMQ SUB socket connected to the manager's event API.
	def make_event_api_socket
		self.log.info "Connecting to the event socket %p" % [ self.event_api_url ]
		sock = Arborist.zmq_context.socket( :SUB )
		sock.connect( self.event_api_url )

		return sock
	end

end # class Arborist::Client