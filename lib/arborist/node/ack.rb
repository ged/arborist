# -*- ruby -*-
#encoding: utf-8

require 'arborist/node' unless defined?( Arborist::Node )
require 'arborist/mixins'


# The inner class for the 'ack' operational property
class Arborist::Node::Ack
	extend Arborist::HashUtilities

	### Construct an instance from the values in the specified +hash+.
	def self::from_hash( hash )
		hash = symbolify_keys( hash )

		message = hash.delete( :message ) or raise ArgumentError, "Missing required ACK message"
		sender  = hash.delete( :sender )  or raise ArgumentError, "Missing required ACK sender"

		if hash[:time]
			hash[:time] = Time.at( hash[:time] ) if hash[:time].is_a?( Numeric )
			hash[:time] = Time.parse( hash[:time] ) unless hash[:time].is_a?( Time )
		end

		return new( message, sender, **hash )
	end


	### Create a new acknowledgement
	def initialize( message, sender, via: nil, time: nil )
		time ||= Time.now

		@message = message
		@sender  = sender
		@via     = via
		@time    = time.to_time
	end

	##
	# The object's message, :sender, :via, :time
	attr_reader :message, :sender, :via, :time


	### Return a string description of the acknowledgement for logging and inspection.
	def description
		return "by %s%s -- %s" % [
			self.sender,
			self.via ? " via #{self.via}" : '',
			self.message
		]
	end


	### Return the Ack as a Hash.
	def to_h( * )
		return {
			message: self.message,
			sender: self.sender,
			via: self.via,
			time: self.time.iso8601,
		}
	end


	### Returns true if the +other+ object is an Ack with the same values.
	def ==( other )
		return other.is_a?( self.class ) &&
			self.to_h == other.to_h
	end

end # class Arborist::Node::Ack


