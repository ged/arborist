# -*- ruby -*-
#encoding: utf-8

require 'msgpack'
require 'loggability'
require 'rbczmq'
require 'arborist/manager' unless defined?( Arborist::Manager )


class Arborist::Manager::TreeAPI < ZMQ::Handler
	extend Loggability


	# Loggability API -- log to the arborist logger
	log_to :arborist


	### Create the TreeAPI handler that will read requests from the specified +pollable+
	### and call into the +manager+ to respond to them.
	def initialize( pollable, manager )
		self.log.debug "Setting up a %p" % [ self.class ]
		super
		@manager = manager
	end


	### ZMQ::Handler API -- Read and handle an incoming request.
	def on_readable
		request = self.recv
		response = self.handle_request( request )
		self.send( response )
	end


	### Handle the specified +raw_request+ and return a response.
	def handle_request( raw_request )
		self.log.debug "Handling request: %p" % [ raw_request ]

		header, body = self.parse_request( raw_request )
		return self.dispatch_request( header, body )

	rescue Arborist::ClientError => err
		self.log.error "%p: %s" % [ err.class, err.message ]
		self.log.debug "  %s" % [ err.backtrace.join( "\n  ") ]
		return self.error_response( 'client', err.message )
	end


	### Attempt to dispatch a request given its +header+ and +body+, and return the
	### serialized response.
	def dispatch_request( header, body )
		handler = self.lookup_request_action( header ) or
			raise Arborist::RequestError, "No such action '%s'" % [ header['action'] ]

		response = handler.call( header, body )

		self.log.debug "Returning response: %p" % [ response ]
		return response
	end


	### Given a request +header+, return a #call-able object that can handle the response.
	def lookup_request_action( header )
		raise Arborist::RequestError, "unsupported version %d" % [ header['version'] ] unless
			header['version'] == 1

		handler_name = "make_%s_response" % [ header['action'] ]
		return nil unless self.respond_to?( handler_name )

		return self.method( handler_name )
	end


	### Build an error response message for the specified +category+ and +reason+.
	def error_response( category, reason )
		msg = [
			{ category: category, reason: reason, success: false, version: 1 }
		]
		return MessagePack.pack( msg )
	end


	### Build a successful response with the specified +body+.
	def successful_response( body )
		msg = [
			{ success: true, version: 1 },
			body
		]
		return MessagePack.pack( msg )
	end


	### Validate and return a parsed msgpack +raw_request+.
	def parse_request( raw_request )
		tuple = begin
			MessagePack.unpack( raw_request )
		rescue => err
			raise Arborist::RequestError, err.message
		end

		raise Arborist::RequestError, 'not a tuple' unless tuple.is_a?( Array )
		raise Arborist::RequestError, 'incorrect length' if tuple.length.zero? || tuple.length > 2

		header, body = *tuple
		raise Arborist::RequestError, "header is not a Map" unless
			header.is_a?( Hash )
		raise Arborist::RequestError, "missing required header 'version'" unless
			header.key?( 'version' )
		raise Arborist::RequestError, "missing required header 'action'" unless
			header.key?( 'action' )

		raise Arborist::RequestError, "body must be a Map or Nil" unless
			body.is_a?( Hash ) || body.nil?

		return header, body
	end


	### Return a repsonse to the `list` action.
	def make_list_response( header, body )
		return successful_response( nodes: @manager.nodelist )
	end


	### Return a response to the `status` action.
	def make_status_response( header, body )
		return successful_response(
			server_version: Arborist::VERSION,
			state: @manager.running? ? 'running' : 'not running',
			uptime: @manager.uptime,
			nodecount: @manager.nodecount
		)
	end


	### Return a response to the 'fetch' action.
	def make_fetch_response( header, body )
		
		return successful_response(  )
	end


end # class Arborist::Manager::TreeAPI

