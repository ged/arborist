# -*- ruby -*-
#encoding: utf-8

require 'arborist' unless defined?( Arborist )
require 'arborist/subscription'


# An inter-node event subscription
class Arborist::NodeSubscription < Arborist::Subscription

	### Create a new subscription object that will send events to the given
	### +node+.
	def initialize( node )
		@node = node
		super()
	end


	######
	public
	######

	##
	# The target node
	attr_reader :node


	### Return the identifier of the subscribed node.
	def node_identifier
		return self.node.identifier
	end


	### Return an ID derived from the node's identifier.
	def generate_id
		return "%s-subscription" % [ self.node_identifier ]
	end


	### Check the node to make sure it can handle published events.
	def check_callback
		raise NameError, "node doesn't implement handle_event" unless
			self.node.respond_to?( :handle_event )
	end


	### Publish any of the specified +events+ which match the subscription.
	def on_events( *events )
		events.flatten.each do |event|
			self.node.handle_event( event )
		end
	end


	### Return a String representation of the object suitable for debugging.
	def inspect
		return "#<%p:%#x for the %s node>" % [
			self.class,
			self.object_id * 2,
			self.node.identifier,
		]
	end


end # class Arborist::NodeSubscription
