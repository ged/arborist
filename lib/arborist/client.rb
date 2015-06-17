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
	end

	# The ZMQ URI required to speak to the Arborist tree API.
	attr_accessor :tree_api_url

	# The ZMQ URI required to speak to the Arborist event API.
	attr_accessor :event_api_url


	### Return the manager's current status as a hash.
	def status
		request = self.pack_message( :status )
		return self.send_tree_api_request( request )
	end


	### Return the manager's current node tree.
	def list
		request = self.pack_message( :list )
		return self.send_tree_api_request( request )
	end


	### Return the manager's current node tree.
	def fetch( search_criteria )
		request = self.pack_message( :fetch, search_criteria )
		return self.send_tree_api_request( request )
	end


	### Update the identified nodes in the manager with the specified data.
	def update( data )
		request = self.pack_message( :update, data )
		return self.send_tree_api_request( request )
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
		body   = data.pop
		header = data.pop || {}
		header.merge!( action: verb, version: API_VERSION )

		return MessagePack.pack([ header, body ])
	end


	### De-serialize an Arborist manager response.
	def unpack_message( msg )
		return MessagePack.unpack( msg )
	end


	### Return a ZMQ REQ communication socket to the manager's tree API,
	### instantiating it if necessary.
	def tree_api
		unless @tree_api
			self.log.info "Connecting to the tree socket %p" % [ self.tree_api_url ]
			@tree_api = Arborist.zmq_context.socket( :REQ )
			@tree_api.connect( self.tree_api_url )
		end
		return @tree_api
	end


	### Return a ZMQ SUB communication socket to the manager's event API,
	### instantiating it if necessary.
	def event_api
		unless @event_api
			self.log.info "Connecting to the event socket %p" % [ self.event_api_url ]
			@event_api = Arborist.zmq_context.socket( :SUB )
			@event_api.connect( self.event_api_url )
		end
		return @event_api
	end


end # class Arborist::Client
