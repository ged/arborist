# -*- ruby -*-
#encoding: utf-8

require 'pluggability'
require 'arborist' unless defined?( Arborist )


# The representation of activity in the manager; events are broadcast when
# node state changes, when they're updated, and when various other operational
# actions take place, e.g., the node tree gets reloaded.
class Arborist::Event
	extend Pluggability


	# Pluggability API -- look for events under the specified prefix
	plugin_prefixes 'arborist/event'


	### Create a new event with the specified +payload+ data.
	def initialize( payload )
		payload = payload.clone unless payload.nil?
		@payload = payload
	end


	######
	public
	######

	# The event payload specific to the event type
	attr_reader :payload


	### Return the type of the event.
	def type
		return self.class.name.
			sub( /.*::/, '' ).
			gsub( /([a-z])([A-Z])/, '\1.\2' ).
			downcase
	end


	### Match operator -- returns +true+ if the other object matches this event.
	def match( object )
		return object.respond_to?( :event_type ) &&
		   ( object.event_type.nil? || object.event_type == self.type )
	end
	alias_method :=~, :match


	### Return the event as a Hash.
	def to_hash
		return {
			'type' => self.type,
			'data' => self.payload
		}
	end

end # class Arborist::Event


