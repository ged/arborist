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


	### Create and return a singleton instance with configured
	### endpoints.
	def self::instance
		return @instance ||= new
	end


	### Create a new Client with the given API socket URIs.
	def initialize( tree_api_url: nil, event_api_url: nil )
		@tree_api_url  = tree_api_url  || Arborist.tree_api_url
		@event_api_url = event_api_url || Arborist.event_api_url
	end


	######
	public
	######

	# The ZeroMQ URI required to speak to the Arborist tree API.
	attr_accessor :tree_api_url

	# The ZeroMQ URI required to speak to the Arborist event API.
	attr_accessor :event_api_url


	#
	# Convenience methods
	#


	### Return dependencies of the given +identifier+ as an array.
	def dependencies_of( identifier, partition: nil, properties: :all )
		dependencies = self.deps( identifier: identifier )[ 'deps' ]
		dependencies = self.search(
			criteria: { identifier: dependencies },
			options:  { properties: properties }
		)

		if partition
			partition = partition.to_s
			dependencies.keys.each{|id| dependencies[id]['identifier'] = id }
			dependencies = dependencies.values.group_by do |node|
				node[ partition ]
			end
		end

		return dependencies
	end


	### Retreive a single node.
	def fetch_node( identifier )
		request = self.make_fetch_request( from: identifier, depth: 0 )
		return self.send_tree_api_request( request ).first
	end


	#
	# Protocol methods
	#

	### Return the manager's current status as a hash.
	def status
		request = self.make_status_request
		return self.send_tree_api_request( request )
	end


	### Return a `status` request as a ZMQ message (a CZTop::Message).
	def make_status_request
		return Arborist::TreeAPI.request( :status )
	end


	### Fetch the manager's current node tree.
	def fetch( **args )
		request = self.make_fetch_request( **args )
		return self.send_tree_api_request( request )
	end


	### Return a `fetch` request as a ZMQ message (a CZTop::Message) with the given
	### attributes.
	def make_fetch_request( from: nil, depth: nil, tree: false )
		header = {}
		self.log.debug "From is: %p" % [ from ]
		header[:from] = from if from
		header[:depth] = depth if depth
		header[:tree] = 'true' if tree

		return Arborist::TreeAPI.request( :fetch, header, nil )
	end


	### Return the manager's current node tree.
	def search( criteria:{}, options:{}, **args )
		criteria = args if criteria.empty?
		request = self.make_search_request( criteria, **options )
		return self.send_tree_api_request( request )
	end


	### Return a `search` request as a ZMQ message (a CZTop::Message) with the given
	### attributes.
	def make_search_request( criteria, exclude_down: false, properties: :all, exclude: {} )
		header = {}
		header[ :exclude_down ] = true if exclude_down
		header[ :return ] = properties if properties != :all

		return Arborist::TreeAPI.request( :search, header, [ criteria, exclude ] )
	end


	### Return the identifiers that have a dependency on the node with the
	### specified +identifier+.
	def deps( identifier: )
		request = self.make_deps_request( identifier )
		return self.send_tree_api_request( request )
	end


	### Return a `deps` request as a ZMQ message (a CZTop::Message) with the given
	### +identifier+.
	def make_deps_request( identifier )
		return Arborist::TreeAPI.request( :deps, { from: identifier }, nil )
	end


	### Update the identified nodes in the manager with the specified data.
	def update( *args )
		request = self.make_update_request( *args )
		self.send_tree_api_request( request )
		return true
	end


	### Return an `update` request as a zmq message (a CZTop::Message) with the given
	### +data+.
	def make_update_request( data, header={} )
		return Arborist::TreeAPI.request( :update, header, data )
	end


	### Add a subscription
	def subscribe( **args )
		request = self.make_subscribe_request( **args )
		response = self.send_tree_api_request( request )
		return response['id']
	end


	### Return a `subscribe` request as a zmq message (a CZTop::Message) with the
	### specified attributes.
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


	### Return an `unsubscribe` request as a zmq message (a CZTop::Message) with the
	### specified +subid+.
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


	### Return a `prune` request as a zmq message (a CZTop::Message) with the
	### specified +identifier+.
	def make_prune_request( identifier: )
		self.log.debug "Making prune request for identifier: %s" % [ identifier ]

		return Arborist::TreeAPI.request( :prune, {identifier: identifier}, nil )
	end


	### Add a new node to the tree.
	def graft( *args )
		request = self.make_graft_request( *args )
		response = self.send_tree_api_request( request )
		return response
	end


	### Return a `graft` request as a zmq message (a CZTop::Message) with the
	### specified attributes.
	def make_graft_request( identifier:, type:, parent: nil, attributes:{} )
		self.log.debug "Making graft request for identifer: %s" % [ identifier ]

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


	### Return a `modify` request as a zmq message (a CZTop::Message) with the
	### specified attributes.
	def make_modify_request( identifier:, attributes: )
		self.log.debug "Making modify request for identifer: %s" % [ identifier ]

		return Arborist::TreeAPI.request( :modify, {identifier: identifier}, attributes )
	end


	### Mark a node as 'acknowledged' if it's down, or 'disabled' if
	### it's up.  (A pre-emptive acknowledgement.)  Requires the node
	### +identifier+, an acknowledgement +message+, and +sender+.  You
	### can optionally include a +via+ (source), and override the default
	### +time+ of now.
	def acknowledge( *args )
		request = self.make_acknowledge_request( *args )
		response = self.send_tree_api_request( request )
		return true
	end
	alias_method :ack, :acknowledge


	### Return an `ack` request as a zmq message (a CZTop::Message) with the specified
	### attributes.
	def make_acknowledge_request( identifier:, message:, sender:, via: nil, time: Time.now )
		ack = {
			message: message,
			sender:  sender,
			via:     via,
			time:    time.to_s
		}

		return Arborist::TreeAPI.request( :ack, {identifier: identifier}, ack )
	end


	### Clear the acknowledgement for a node.
	def clear_acknowledgement( *args )
		request = self.make_unack_request( *args )
		response = self.send_tree_api_request( request )
		return true
	end
	alias_method :unack, :clear_acknowledgement
	alias_method :clear_ack, :clear_acknowledgement
	alias_method :unacknowledge, :clear_acknowledgement


	### Return an `unack` request as a zmq message (a CZTop::Message) with the specified
	### attribute.
	def make_unack_request( identifier: )
		return Arborist::TreeAPI.request( :unack, {identifier: identifier}, nil )
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
			exception = header['category'] == 'client' ? Arborist::ClientError : Arborist::ServerError
			raise exception, "Arborist manager said: %s" % [ header['reason'] ]
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
