# -*- ruby -*-
#encoding: utf-8

require 'msgpack'
require 'loggability'
require 'cztop'
require 'arborist' unless defined?( Arborist )


module Arborist::EventAPI
	extend Loggability


	# Loggability API -- log to arborist's logger
	log_to :arborist


	### Encode an event with the specified +identifier+ and +payload+ as a
	### CZTop::Message and return it.
	def self::encode( identifier, payload )
		encoded_payload = MessagePack.pack( payload )
		return CZTop::Message.new([ identifier, encoded_payload ])
	end


	### Decode and return the identifier and payload from the specified +msg+ (a CZTop::Message).
	def self::decode( msg )
		identifier, encoded_payload = msg.to_a
		payload = MessagePack.unpack( encoded_payload )
		return identifier, payload
	end


end # class Arborist::Manager::EventPublisher

