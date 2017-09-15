# -*- ruby -*-
#encoding: utf-8

require 'msgpack'

require 'arborist' unless defined?( Arborist )
require 'arborist/tree_api'


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

		@request_queue = nil
		@event_subscriptions = nil
	end


	######
	public
	######

	# The ZeroMQ URI required to speak to the Arborist tree API.
	attr_accessor :tree_api_url

	# The ZeroMQ URI required to speak to the Arborist event API.
	attr_accessor :event_api_url


	#
	# High-level methods
	#

	### Mark a node as 'acknowledged' if it's down, or 'disabled' if
	### it's up.  (A pre-emptive acknowledgement.)  Requires the node
	### +identifier+, an acknowledgement +message+, and +sender+.  You
	### can optionally include a +via+ (source), and override the default
	### +time+ of now.
	def acknowledge( identifier:, message:, sender:, via: nil, time: Time.now )
		data = {
			identifier => {
				ack: {
					message: message,
					sender:  sender,
					via:     via,
					time:    time.to_s
				}
			}
		}

		return self.update( data )
	end
	alias_method :ack, :acknowledge


	### Clear an acknowledged/disabled node +identifier+.
	def clear_acknowledgement( identifier: )
		data = { identifier => { ack: nil } }
		request = self.make_update_request( data )
		self.send_tree_api_request( request )
		return true
	end
	alias_method :clear_ack, :clear_acknowledgement



	#
	# Protocol methods
	#

	### Return the manager's current status as a hash.
	def status
		request = self.make_status_request
		return self.send_tree_api_request( request )
	end


	### Return the manager's current status as a hash.
	def make_status_request
		return Arborist::TreeAPI.request( :status )
	end


	### Return the manager's current node tree.
	def fetch( **args )
		request = self.make_fetch_request( **args )
		return self.send_tree_api_request( request )
	end


	### Return the manager's current node tree.
	def make_fetch_request( from: nil, depth: nil, tree: false )
		header = {}
		self.log.debug "From is: %p" % [ from ]
		header[:from] = from if from
		header[:depth] = depth if depth
		header[:tree] = 'true' if tree

		return Arborist::TreeAPI.request( :fetch, header, nil )
	end


	### Return the manager's current node tree.
	def search( criteria={}, options={} )
		request = self.make_search_request( criteria, **options )
		return self.send_tree_api_request( request )
	end


	### Return the manager's current node tree.
	def make_search_request( criteria, include_down: false, properties: :all, exclude: {} )
		header = {}
		header[ :include_down ] = true if include_down
		header[ :return ] = properties if properties != :all

		return Arborist::TreeAPI.request( :search, header, [ criteria, exclude ] )
	end


	### Update the identified nodes in the manager with the specified data.
	def update( *args )
		request = self.make_update_request( *args )
		self.send_tree_api_request( request )
		return true
	end


	### Update the identified nodes in the manager with the specified data.
	def make_update_request( data )
		return Arborist::TreeAPI.request( :update, nil, data )
	end


	### Add a subscription
	def subscribe( **args )
		request = self.make_subscribe_request( **args )
		response = self.send_tree_api_request( request )
		return response['id']
	end


	### Make a subscription request for the specified +criteria+, +identifier+, and +event_type+.
	def make_subscribe_request( criteria: {}, identifier: nil, event_type: nil, exclude: {} )
		self.log.debug "Making subscription request for identifier: %p, event_type: %p, criteria: %p" %
			[ identifier, event_type, criteria ]
		header = {}
		header[ :identifier ] = identifier if identifier
		header[ :event_type ] = event_type

		return Arborist::TreeAPI.request( :subscribe, header, [ criteria, exclude ] )
	end


	### Remove a subscription
	def unsubscribe( *args )
		request = self.make_unsubscribe_request( *args )
		response = self.send_tree_api_request( request )
		return response
	end


	### Remove the subscription with the specified +subid+.
	def make_unsubscribe_request( subid )
		self.log.debug "Making unsubscribe request for subid: %s" % [ subid ]

		return Arborist::TreeAPI.request( :unsubscribe, {subscription_id: subid}, nil )
	end


	### Remove a node
	def prune( *args )
		request = self.make_prune_request( *args )
		response = self.send_tree_api_request( request )
		return response
	end


	### Remove the node with the specified +identfier+.
	def make_prune_request( identifier )
		self.log.debug "Making prune request for identifier: %s" % [ identifier ]

		return Arborist::TreeAPI.request( :prune, {identifier: identifier}, nil )
	end


	### Add a new node to the tree.
	def graft( *args )
		request = self.make_graft_request( *args )
		response = self.send_tree_api_request( request )
		return response
	end


	### Add a node with the specified +identifier+ and +arguments+.
	def make_graft_request( identifier, attributes={} )
		self.log.debug "Making graft request for identifer: %s" % [ identifier ]

		parent = attributes.delete( :parent )
		type   = attributes.delete( :type )

		header = {
			identifier: identifier,
			parent:     parent,
			type:       type
		}

		return Arborist::TreeAPI.request( :graft, header, attributes )
	end


	### Modify operational attributes of a node.
	def modify( *args )
		request = self.make_modify_request( *args )
		response = self.send_tree_api_request( request )
		return true
	end


	### Modify the operations +attributes+ of the node with the specified +identifier+.
	def make_modify_request( identifier, attributes={} )
		self.log.debug "Making modify request for identifer: %s" % [ identifier ]

		return Arborist::TreeAPI.request( :modify, {identifier: identifier}, attributes )
	end


	### Send the packed +request+ via the Tree API socket, raise an error on
	### unsuccessful response, and return the response body.
	def send_tree_api_request( request )
		self.log.debug "Sending request: %p" % [ request ]
		request.send_to( self.tree_api )

		res = CZTop::Message.receive_from( self.tree_api )
		self.log.debug "Received response: %p" % [ res ]

		header, body = Arborist::TreeAPI.decode( res )
		unless header[ 'success' ]
			raise "Arborist manager said: %s" % [ header['reason'] ]
		end

		return body
	end


	#
	# Utility methods
	#

	### Return a ZeroMQ REQ socket connected to the manager's tree API, instantiating
	### it if necessary.
	def tree_api
		return @tree_api ||= self.make_tree_api_socket
	end


	### Create a new ZMQ REQ socket connected to the manager's tree API.
	def make_tree_api_socket
		self.log.info "Connecting to the tree socket %p" % [ self.tree_api_url ]
		return CZTop::Socket::REQ.new( self.tree_api_url )
	end


	### Return a ZMQ SUB socket connected to the manager's event API, instantiating
	### it if necessary.
	def event_api
		return @event_api ||= self.make_event_api_socket
	end


	### Create a new ZMQ SUB socket connected to the manager's event API.
	def make_event_api_socket
		self.log.info "Connecting to the event socket %p" % [ self.event_api_url ]
		return CZTop::Socket::SUB.new( self.event_api_url )
	end

end # class Arborist::Client
