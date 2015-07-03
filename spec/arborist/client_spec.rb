#!/usr/bin/env rspec -cfd

require_relative '../spec_helper'

require 'arborist/client'


describe Arborist::Client do

	let( :client ) { described_class.new }

	describe "synchronous API", :testing_manager do

		before( :each ) do
			Arborist.reset_zmq_context

			@manager = make_testing_manager()
			@manager_thread = Thread.new do
				Thread.current.abort_on_exception = true
				manager.run
				Loggability[ Arborist ].info "Stopped the test manager"
			end

			count = 0
			until manager.running? || count > 30
				sleep 0.1
				count += 1
			end
			raise "Manager didn't start up" unless manager.running?
		end

		after( :each ) do
			@manager.stop
			@manager_thread.join

			count = 0
			while @manager.zmq_loop.running? || count > 30
				sleep 0.1
				Loggability[ Arborist ].info "ZMQ loop still running"
				count += 1
			end
			raise "ZMQ Loop didn't stop" if @manager.zmq_loop.running?
		end


		let( :manager ) { @manager }


		it "can fetch the status of the manager it's connected to" do
			res = client.status
			expect( res ).to include( 'server_version', 'state', 'uptime', 'nodecount' )
		end


		it "can list the nodes of the manager it's connected to" do
			res = client.list
			expect( res ).to be_an( Array )
			expect( res.length ).to eq( manager.nodes.length )
		end


		it "can list a subtree of the nodes of the manager it's connected to" do
			res = client.list( from: 'duir' )
			expect( res ).to be_an( Array )
			expect( res.length ).to be < manager.nodes.length
		end


		it "can fetch all node properties for all 'up' nodes" do
			res = client.fetch
			expect( res ).to be_a( Hash )
			expect( res.length ).to be == manager.nodes.length
			expect( res.values ).to all( be_a(Hash) )
		end


		it "can fetch identifiers for all 'up' nodes" do
			res = client.fetch( {}, properties: nil )
			expect( res ).to be_a( Hash )
			expect( res.length ).to be == manager.nodes.length
			expect( res.values ).to all( be_nil )
		end


		it "can fetch a subset of properties for all 'up' nodes" do
			res = client.fetch( {}, properties: [:addresses, :status] )
			expect( res ).to be_a( Hash )
			expect( res.length ).to be == manager.nodes.length
			expect( res.values ).to all( be_a(Hash) )
			expect( res.values.map(&:length) ).to all( be <= 2 )
		end


		it "can fetch a subset of properties for all 'up' nodes matching specified criteria" do
			res = client.fetch( {type: 'host'}, properties: [:addresses, :status] )
			expect( res ).to be_a( Hash )
			expect( res.length ).to be == manager.nodes.values.count {|n| n.type == 'host' }
			expect( res.values ).to all( include('addresses', 'status') )
		end


		it "can fetch all properties for all nodes regardless of their status" do
			# Down a node
			manager.nodes['duir'].update( error: 'something happened' )

			res = client.fetch( {type: 'host'}, include_down: true )

			expect( res ).to be_a( Hash )
			expect( res ).to include( 'duir' )
			expect( res['duir']['status'] ).to eq( 'down' )
		end


		it "can update the properties of managed nodes" do
			client.update( duir: { ping: {rtt: 24} } )

			expect( manager.nodes['duir'].properties ).to include( 'ping' )
			expect( manager.nodes['duir'].properties['ping'] ).to include( 'rtt' )
			expect( manager.nodes['duir'].properties['ping']['rtt'] ).to eq( 24 )
		end

	end


	describe "asynchronous API" do

		it "can make a raw status request" do
			req = client.make_status_request
			expect( req ).to be_a( String )
			expect( req.encoding ).to eq( Encoding::ASCII_8BIT )

			msg = unpack_message( req )
			expect( msg ).to be_an( Array )
			expect( msg.first ).to be_a( Hash )
			expect( msg.first ).to include( 'version', 'action' )
			expect( msg.first['version'] ).to eq( Arborist::Client::API_VERSION )
			expect( msg.first['action'] ).to eq( 'status' )
		end


		it "can make a raw list request" do
			req = client.make_list_request
			expect( req ).to be_a( String )
			expect( req.encoding ).to eq( Encoding::ASCII_8BIT )

			msg = unpack_message( req )
			expect( msg ).to be_an( Array )
			expect( msg.first ).to be_a( Hash )
			expect( msg.first ).to include( 'version', 'action' )
			expect( msg.first ).to_not include( 'from' )
			expect( msg.first['version'] ).to eq( Arborist::Client::API_VERSION )
			expect( msg.first['action'] ).to eq( 'list' )
		end


		it "can make a raw fetch request" do
			req = client.make_fetch_request( {} )
			expect( req ).to be_a( String )
			expect( req.encoding ).to eq( Encoding::ASCII_8BIT )

			msg = unpack_message( req )
			expect( msg ).to be_an( Array )
			expect( msg.first ).to be_a( Hash )
			expect( msg.first ).to include( 'version', 'action' )
			expect( msg.first['version'] ).to eq( Arborist::Client::API_VERSION )
			expect( msg.first['action'] ).to eq( 'fetch' )

			expect( msg.last ).to eq( {} )
		end


		it "can make a raw fetch request with criteria" do
			req = client.make_fetch_request( {type: 'host'} )
			expect( req ).to be_a( String )
			expect( req.encoding ).to eq( Encoding::ASCII_8BIT )

			msg = unpack_message( req )
			expect( msg ).to be_an( Array )
			expect( msg.first ).to be_a( Hash )
			expect( msg.first ).to include( 'version', 'action' )
			expect( msg.first['version'] ).to eq( Arborist::Client::API_VERSION )
			expect( msg.first['action'] ).to eq( 'fetch' )

			expect( msg.last ).to be_a( Hash )
			expect( msg.last ).to include( 'type' )
			expect( msg.last['type'] ).to eq( 'host' )
		end


		it "can make a raw update request" do
			req = client.make_update_request( duir: {error: "Something happened."} )
			expect( req ).to be_a( String )
			expect( req.encoding ).to eq( Encoding::ASCII_8BIT )

			msg = unpack_message( req )
			expect( msg ).to be_an( Array )
			expect( msg.first ).to be_a( Hash )
			expect( msg.first ).to include( 'version', 'action' )
			expect( msg.first['version'] ).to eq( Arborist::Client::API_VERSION )
			expect( msg.first['action'] ).to eq( 'update' )

			expect( msg.last ).to be_a( Hash )
			expect( msg.last ).to include( 'duir' )
			expect( msg.last['duir'] ).to eq( 'error' => 'Something happened.' )
		end

	end


end

