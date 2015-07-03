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
		@pollitem = pollable
		@manager  = manager
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

	rescue => err
		self.log.error "%p: %s" % [ err.class, err.message ]
		err.backtrace.each {|frame| self.log.debug "  #{frame}" }

		errtype = err.is_a?( Arborist::RequestError ) ? 'client' : 'server'
		return self.error_response( errtype, err.message )
	end


	### Attempt to dispatch a request given its +header+ and +body+, and return the
	### serialized response.
	def dispatch_request( header, body )
		self.log.debug "Dispatching request %p -> %p" % [ header, body ]
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

		handler_name = "handle_%s_request" % [ header['action'] ]
		return nil unless self.respond_to?( handler_name )

		return self.method( handler_name )
	end


	### Build an error response message for the specified +category+ and +reason+.
	def error_response( category, reason )
		msg = [
			{ category: category, reason: reason, success: false, version: 1 }
		]
		self.log.debug "Returning error response: %p" % [ msg ]
		return MessagePack.pack( msg )
	end


	### Build a successful response with the specified +body+.
	def successful_response( body )
		msg = [
			{ success: true, version: 1 },
			body
		]
		self.log.debug "Returning successful response: %p" % [ msg ]
		return MessagePack.pack( msg )
	end


	### Validate and return a parsed msgpack +raw_request+.
	def parse_request( raw_request )
		tuple = begin
			MessagePack.unpack( raw_request )
		rescue => err
			raise Arborist::RequestError, err.message
		end

		self.log.debug "Parsed request: %p" % [ tuple ]

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


	### Return a response to the `status` action.
	def handle_status_request( header, body )
		self.log.info "STATUS: %p" % [ header ]
		return successful_response(
			server_version: Arborist::VERSION,
			state: @manager.running? ? 'running' : 'not running',
			uptime: @manager.uptime,
			nodecount: @manager.nodecount
		)
	end


	### Return a repsonse to the `list` action.
	def handle_list_request( header, body )
		self.log.info "LIST: %p" % [ header ]
		from = header['from'] || '_'

		start_node = @manager.nodes[ from ]
		self.log.debug "  Listing nodes under %p" % [ start_node ]
		iter = @manager.enumerator_for( start_node )
		data = iter.map( &:to_hash )
		self.log.debug "  got data for %d nodes" % [ data.length ]

		return successful_response( data )
	end


	### Return a response to the 'fetch' action.
	def handle_fetch_request( header, body )
		self.log.info "FETCH: %p" % [ header ]

		nodes_iter = if header['include_down']
				@manager.all_nodes
			else
				@manager.reachable_nodes
			end

		states = nodes_iter.
			select {|node| node.matches?(body) }.
			each_with_object( {} ) do |node, hash|
				if !header.key?( 'return' ) || header['return']
					hash[ node.identifier ] = node.fetch_values( header['return'] )
				else
					hash[ node.identifier ] = nil
				end
			end

		return successful_response( states )
	end


	### Update nodes using the data from the update request's +body+.
	def handle_update_request( header, body )
		self.log.info "UPDATE: %p" % [ header ]

		body.each do |identifier, properties|
			unless (( node = @manager.nodes[ identifier ] ))
				self.log.warn "Update for non-existent node %p ignored." % [ identifier ]
				next
			end

			node.update( properties )
		end

		return successful_response( nil )
	end

end # class Arborist::Manager::TreeAPI
