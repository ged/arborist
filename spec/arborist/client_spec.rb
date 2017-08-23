#!/usr/bin/env rspec -cfd

require_relative '../spec_helper'

require 'arborist/client'


describe Arborist::Client do

	let( :client ) { described_class.new }

	describe "synchronous API", :testing_manager do

		before( :each ) do
			@manager_thread = Thread.new do
				@manager = make_testing_manager()
				Loggability[ Arborist ].info "Starting a testing manager: %p" % [ @manager ]
				Thread.current.abort_on_exception = true
				@manager.run
				Loggability[ Arborist ].info "Stopped the test manager"
			end

			count = 0
			until (@manager && @manager.running?) || count > 30
				sleep 0.1
				count += 1
			end
			raise "Manager didn't start up" unless @manager && @manager.running?
		end

		after( :each ) do
			if @manager
				@manager.simulate_signal( :TERM )
				@manager_thread.join

				count = 0
				while @manager.running? || count > 30
					sleep 0.1
					Loggability[ Arborist ].info "Manager still running"
					count += 1
				end
				raise "Manager didn't stop" if @manager.running?
			end
		end


		let( :manager ) { @manager }


		describe "high-level methods" do

			it "provides a convenience method for acknowledging" do
				manager.nodes['sidonie'].update( error: "Clown apocalypse" )

				res = client.acknowledge( :sidonie, "I'm on it.", "ged" )

				expect( manager.nodes['sidonie'] ).to be_acked
			end


			it "provides a convenience method for clearing acknowledgments" do
				manager.nodes['sidonie'].update( error: "Clown apocalypse" )

				res = client.acknowledge( :sidonie, "I'm on it.", "ged" )
				res = client.clear_acknowledgement( :sidonie )

				expect( manager.nodes['sidonie'] ).to_not be_acked
			end

		end


		describe "protocol-level API" do

			it "can fetch the status of the manager it's connected to" do
				res = client.status
				expect( res ).to include( 'server_version', 'state', 'uptime', 'nodecount' )
			end


			it "can fetch the nodes of the manager it's connected to" do
				res = client.fetch
				expect( res ).to be_an( Array )
				expect( res.length ).to eq( manager.nodes.length )
			end


			it "can fetch a subtree of the nodes of the manager it's connected to" do
				res = client.fetch( from: 'duir' )
				expect( res ).to be_an( Array )
				expect( res.length ).to be < manager.nodes.length
			end


			it "can fetch a depth-limited subtree of the node of the managed it's connected to" do
				res = client.fetch( depth: 2 )
				expect( res ).to be_an( Array )
				expect( res.length ).to eq( 8 )
			end


			it "can fetch a depth-limited subtree of the nodes of the manager it's connected to" do
				res = client.fetch( from: 'duir', depth: 1 )
				expect( res ).to be_an( Array )
				expect( res.length ).to eq( 5 )
			end


			it "can search all node properties for all 'up' nodes" do
				res = client.search
				expect( res ).to be_a( Hash )
				expect( res.length ).to be == manager.nodes.length
				expect( res.values ).to all( be_a(Hash) )
			end


			it "can search identifiers for all 'up' nodes" do
				res = client.search( {}, properties: nil )
				expect( res ).to be_a( Hash )
				expect( res.length ).to be == manager.nodes.length
				expect( res.values ).to all( be_empty )
			end


			it "can search a subset of properties for all 'up' nodes" do
				res = client.search( {}, properties: [:addresses, :status] )
				expect( res ).to be_a( Hash )
				expect( res.length ).to be == manager.nodes.length
				expect( res.values ).to all( be_a(Hash) )
				expect( res.values.map(&:length) ).to all( be <= 2 )
			end


			it "can search a subset of properties for all 'up' nodes matching specified criteria" do
				res = client.search( {type: 'host'}, properties: [:addresses, :status] )
				expect( res ).to be_a( Hash )
				expect( res.length ).to be == manager.nodes.values.count {|n| n.type == 'host' }
				expect( res.values ).to all( include('addresses', 'status') )
			end


			it "can search all node properties for 'up' nodes that don't match specified criteria" do
				res = client.search( {}, properties: [:addresses, :status], exclude: {tag: 'testing'} )

				testing_nodes = manager.nodes.values.select {|n| n.tags.include?('testing') }

				expect( res ).to be_a( Hash )
				expect( res ).to_not be_empty()
				expect( res.length ).to eq( manager.nodes.length - testing_nodes.length )
				expect( res.values ).to all( be_a(Hash) )
			end


			it "can search all properties for all nodes regardless of their status" do
				# Down a node
				manager.nodes['duir'].update( error: 'something happened' )

				res = client.search( {type: 'host'}, include_down: true )

				expect( res ).to be_a( Hash )
				expect( res ).to include( 'duir' )
				expect( res['duir']['status'] ).to eq( 'down' )
			end


			it "can update the properties of managed nodes", :no_ci do
				res = client.update( duir: { ping: {rtt: 24} } )

				expect( res ).to be_truthy
				expect( manager.nodes['duir'].properties ).to include( 'ping' )
				expect( manager.nodes['duir'].properties['ping'] ).to include( 'rtt' )
				expect( manager.nodes['duir'].properties['ping']['rtt'] ).to eq( 24 )
			end


			it "can subscribe to all events" do
				sub_id = client.subscribe
				expect( sub_id ).to be_a( String )
				expect( sub_id ).to match( /^[\w\-]{16,}/ )

				node = manager.subscriptions[ sub_id ]
				sub = manager.root.subscriptions[ sub_id ]

				expect( sub ).to be_a( Arborist::Subscription )
				expect( sub.criteria ).to be_empty
				expect( sub.event_type ).to be_nil
			end


			it "can subscribe to a particular kind of event" do
				sub_id = client.subscribe( event_type: 'node.ack' )
				expect( sub_id ).to be_a( String )
				expect( sub_id ).to match( /^[\w\-]{16,}/ )

				node = manager.subscriptions[ sub_id ]
				sub = manager.root.subscriptions[ sub_id ]

				expect( sub ).to be_a( Arborist::Subscription )
				expect( sub.criteria ).to be_empty
				expect( sub.event_type ).to eq( 'node.ack' )
			end


			it "can subscribe to events for descendants of a particular node in the tree" do
				sub_id = client.subscribe( identifier: 'sidonie' )
				expect( sub_id ).to be_a( String )
				expect( sub_id ).to match( /^[\w\-]{16,}/ )

				node = manager.subscriptions[ sub_id ]
				sub = node.subscriptions[ sub_id ]

				expect( node.identifier ).to eq( 'sidonie' )
				expect( sub ).to be_a( Arborist::Subscription )
				expect( sub.criteria ).to be_empty
				expect( sub.event_type ).to be_nil
			end


			it "can subscribe to events of a particular type for descendants of a particular node" do
				sub_id = client.subscribe( identifier: 'sidonie', event_type: 'node.delta' )
				expect( sub_id ).to be_a( String )
				expect( sub_id ).to match( /^[\w\-]{16,}/ )

				node = manager.subscriptions[ sub_id ]
				sub = node.subscriptions[ sub_id ]

				expect( node.identifier ).to eq( 'sidonie' )
				expect( sub ).to be_a( Arborist::Subscription )
				expect( sub.criteria ).to be_empty
				expect( sub.event_type ).to eq( 'node.delta' )
			end


			it "can subscribe to events matching one or more criteria" do
				sub_id = client.subscribe( criteria: {type: 'service'} )
				expect( sub_id ).to be_a( String )
				expect( sub_id ).to match( /^[\w\-]{16,}/ )

				node = manager.subscriptions[ sub_id ]
				sub = node.subscriptions[ sub_id ]

				expect( node.identifier ).to eq( '_' )
				expect( sub ).to be_a( Arborist::Subscription )
				expect( sub.criteria ).to eq( 'type' => 'service' )
				expect( sub.event_type ).to eq( nil )
			end


			it "can unsubscribe from events using a subscription ID" do
				sub_id = client.subscribe
				res = client.unsubscribe( sub_id )
				expect( res ).to be_truthy
				expect( manager.subscriptions ).to_not include( sub_id )
			end


			it "returns nil without error when unsubscribing to a non-existant subscription" do
				res = client.unsubscribe( 'a_subid' )
				expect( res ).to be_nil
			end


			it "can prune nodes from the tree" do
				res = client.prune( 'sidonie-ssh' )

				expect( res ).to be_a( Hash )
				expect( res ).to include( 'identifier' => 'sidonie-ssh' )
				expect( manager.nodes ).to_not include( 'sidonie-ssh' )
			end


			it "returns nil without error when pruning a node that doesn't exist" do
				res = client.prune( 'carrigor' )
				expect( res ).to be_nil
			end


			it "can graft new nodes onto the tree" do
				res = client.graft( 'breakfast-burrito', type: 'host' )
				expect( res ).to eq({ 'identifier' => 'breakfast-burrito' })
				expect( manager.nodes ).to include( 'breakfast-burrito' )
				expect( manager.nodes['breakfast-burrito'] ).to be_a( Arborist::Node::Host )
				expect( manager.nodes['breakfast-burrito'].parent ).to eq( '_' )
			end


			it "can graft nodes with attributes onto the tree" do
				res = client.graft( 'breakfast-burrito',
					type: 'service',
					parent: 'duir',
					port: 9999,
					tags: ['yusss']
				)
				expect( res ).to eq({ 'identifier' => 'duir-breakfast-burrito' })
				expect( manager.nodes ).to include( 'duir-breakfast-burrito' )
				expect( manager.nodes['duir-breakfast-burrito'] ).to be_a( Arborist::Node::Service )
				expect( manager.nodes['duir-breakfast-burrito'].parent ).to eq( 'duir' )
				expect( manager.nodes['duir-breakfast-burrito'].port ).to eq( 9999 )
				expect( manager.nodes['duir-breakfast-burrito'].tags ).to include( 'yusss' )
			end


			it "can modify operational attributes of a node" do
				res = client.modify( "duir", tags: 'girlrobot' )
				expect( res ).to be_truthy
				expect( manager.nodes['duir'].tags ).to eq( ['girlrobot'] )
			end

		end

	end


	describe "asynchronous API" do

		it "can make a raw status request" do
			req = client.make_status_request
			expect( req ).to be_a( CZTop::Message )

			header, body = Arborist::TreeAPI.decode( req )

			expect( header ).to be_a( Hash )
			expect( header ).to include( 'version', 'action' )
			expect( header['version'] ).to eq( Arborist::Client::API_VERSION )
			expect( header['action'] ).to eq( 'status' )
		end


		it "can make a raw fetch request" do
			req = client.make_fetch_request
			expect( req ).to be_a( CZTop::Message )

			header, body = Arborist::TreeAPI.decode( req )

			expect( header ).to be_a( Hash )
			expect( header ).to include( 'version', 'action' )
			expect( header ).to_not include( 'from' )
			expect( header['version'] ).to eq( Arborist::Client::API_VERSION )
			expect( header['action'] ).to eq( 'fetch' )
		end


		it "can make a raw search request" do
			req = client.make_search_request( {} )
			expect( req ).to be_a( CZTop::Message )

			header, body = Arborist::TreeAPI.decode( req )

			expect( header ).to be_a( Hash )
			expect( header ).to include( 'version', 'action' )
			expect( header['version'] ).to eq( Arborist::Client::API_VERSION )
			expect( header['action'] ).to eq( 'search' )

			expect( body ).to eq([ {}, {} ])
		end


		it "can make a raw search request with criteria" do
			req = client.make_search_request( {type: 'host'} )
			expect( req ).to be_a( CZTop::Message )

			header, body = Arborist::TreeAPI.decode( req )

			expect( header ).to be_a( Hash )
			expect( header ).to include( 'version', 'action' )
			expect( header['version'] ).to eq( Arborist::Client::API_VERSION )
			expect( header['action'] ).to eq( 'search' )

			body = body
			expect( body.first ).to be_a( Hash )
			expect( body.first ).to include( 'type' )
			expect( body.first['type'] ).to eq( 'host' )
		end


		it "can make a raw update request" do
			req = client.make_update_request( duir: {error: "Something happened."} )
			expect( req ).to be_a( CZTop::Message )

			header, body = Arborist::TreeAPI.decode( req )

			expect( header ).to be_a( Hash )
			expect( header ).to include( 'version', 'action' )
			expect( header['version'] ).to eq( Arborist::Client::API_VERSION )
			expect( header['action'] ).to eq( 'update' )

			expect( body ).to be_a( Hash )
			expect( body ).to include( 'duir' )
			expect( body['duir'] ).to eq( 'error' => 'Something happened.' )
		end

	end


end

