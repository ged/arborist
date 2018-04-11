# -*- ruby -*-
#encoding: utf-8

require 'loggability'
require 'pluggability'
require 'arborist' unless defined?( Arborist )


# The representation of activity in the manager; events are broadcast when
# node state changes, when they're updated, and when various other operational
# actions take place, e.g., the node tree gets reloaded.
class Arborist::Event
	extend Pluggability,
	       Loggability


	# Pluggability API -- look for events under the specified prefix
	plugin_prefixes 'arborist/event'

	# Loggability API -- log to the Arborist logger
	log_to :arborist


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
		rval = object.respond_to?( :event_type ) &&
		   ( object.event_type.nil? || object.event_type == self.type )
		self.log.debug "Base node #match: %p" % [ rval ]
		return rval
	end
	alias_method :=~, :match


	### Return the event as a Hash.
	def to_h
		return {
			type: self.type,
			data: self.payload
		}
	end


	### Return a string representation of the object suitable for debugging.
	def inspect
		return "#<%p:%#016x %s>" % [
			self.class,
			self.object_id * 2,
			self.inspect_details,
		]
	end


	### Return the detail portion of the #inspect string appropriate for this event type.
	def inspect_details
		return self.payload.inspect
	end

end # class Arborist::Event


