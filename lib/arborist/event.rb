# -*- ruby -*-
#encoding: utf-8

require 'arborist' unless defined?( Arborist )


# The representation of activity in the manager; events are broadcast when
# node state changes, when they're updated, and when various other operational
# actions take place, e.g., the node tree gets reloaded.
class Arborist::Event

	### Create a new event with the specified +type+ and event +data+.
	def initialize( type, data={} )
		@type = type
		@data = data.clone
	end


	######
	public
	######

	# The event type
	attr_reader :type

	# The event data
	attr_reader :data


end # class Arborist::Event


