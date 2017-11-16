# -*- ruby -*-
#encoding: utf-8

require 'msgpack'
require 'loggability'
require 'cztop'
require 'arborist' unless defined?( Arborist )


module Arborist::TreeAPI
	extend Loggability,
	       Arborist::MethodUtilities,
	       Arborist::HashUtilities

	# The version of the application protocol
	PROTOCOL_VERSION = 1


	# Loggability API -- log to the arborist logger
	log_to :arborist



	### Return a CZTop::Message with a payload containing the specified +header+ and +body+.
	def self::encode( header, body=nil )
		raise Arborist::MessageError, "header is not a Map" unless
			header.is_a?( Hash )

		# self.log.debug "Encoding header: %p with body: %p" % [ header, body ]
		header = stringify_keys( header )
		header['version'] = PROTOCOL_VERSION

		self.check_header( header )
		self.check_body( body )

		payload = MessagePack.pack([ header, body ])

		# self.log.debug "Making zmq message with payload: %p" % [ payload ]
		return CZTop::Message.new( payload )
	end


	### Return the header and body from the TreeAPI request or response in the specified +msg+
	### (a CZTop::Message).
	def self::decode( msg )
		raw_message = msg.pop or raise Arborist::MessageError, "empty message"

		parts = begin
			MessagePack.unpack( raw_message )
		rescue => err
			raise Arborist::MessageError, err.message
		end

		raise Arborist::MessageError, 'not an Array' unless parts.is_a?( Array )
		raise Arborist::MessageError,
			"malformed message: expected 1-2 parts, got %d" % [ parts.length ] unless
			parts.length.between?( 1, 2 )

		header = parts.shift or
			raise Arborist::MessageError, "no header"
		self.check_header( header )

		body = parts.shift
		self.check_body( body )

		return header, body
	end


	### Return a CZTop::Message containing a TreeAPI request with the specified
	### +verb+ and +data+.
	def self::request( verb, *data )
		body   = data.pop
		header = data.pop || {}

		header.merge!( action: verb )

		return self.encode( header, body )
	end


	### Build an error response message for the specified +category+ and +reason+.
	def self::error_response( category, reason )
		return self.encode({ category: category, reason: reason, success: false })
	end


	### Build a successful response with the specified +body+.
	def self::successful_response( body )
		return self.encode({ success: true }, body )
	end


	### Check the given +header+ for validity, raising an Arborist::MessageError if
	### it isn't.
	def self::check_header( header )
		raise Arborist::MessageError, "header is not a Map" unless
			header.is_a?( Hash )
		version = header['version'] or
			raise Arborist::MessageError, "missing required header 'version'"
		raise Arborist::MessageError, "unknown protocol version %p" % [version] unless
			version == PROTOCOL_VERSION
	end


	### Check the given +body+ for validity, raising an Arborist::MessageError if it
	### isn't.
	def self::check_body( body )
		unless body.is_a?( Hash ) ||
			   body.nil? ||
		       ( body.is_a?(Array) && body.all? {|obj| obj.is_a?(Hash) } )
			self.log.error "Invalid message body: %p" % [ body]
			raise Arborist::MessageError, "body must be Nil, a Map, or an Array of Maps"
		end
	end

end # class Arborist::TreeAPI

