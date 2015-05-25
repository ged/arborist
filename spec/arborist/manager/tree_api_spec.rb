#!/usr/bin/env rspec -cfd

require_relative '../../spec_helper'


describe Arborist::Manager::TreeAPI, :testing_manager do

	before( :each ) do
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
		while ZMQ::Loop.running? || count > 30
			sleep 0.1
			Loggability[ Arborist ].info "ZMQ loop still running"
			count += 1
		end
		raise "ZMQ Loop didn't stop" if ZMQ::Loop.running?
	end


	let( :manager ) { @manager }

	let!( :sock ) do
		sock = Arborist.zmq_context.socket( :REQ )
		sock.linger = 0
		sock.connect( TESTING_API_SOCK )
		sock
	end

	let( :api_handler ) { described_class.new( rep_sock, manager ) }


	describe "malformed requests" do

		it "send an error response if the request can't be deserialized" do
			sock.send( "whatevs, dude!" )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include(
				'success'  => false,
				'reason'   => /invalid request/i,
				'category' => 'client'
			)
			expect( body ).to be_nil
		end


		it "send an error response if the request isn't a tuple" do
			sock.send( MessagePack.pack({ version: 1, action: 'list' }) )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include(
				'success'  => false,
				'reason'   => /invalid request.*not a tuple/i,
				'category' => 'client'
			)
			expect( body ).to be_nil
		end


		it "send an error response if the request is empty" do
			sock.send( MessagePack.pack([]) )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include(
				'success'  => false,
				'reason'   => /invalid request.*incorrect length/i,
				'category' => 'client'
			)
			expect( body ).to be_nil
		end


		it "send an error response if the request is an incorrect length" do
			sock.send( MessagePack.pack([{}, {}, {}]) )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include(
				'success'  => false,
				'reason'   => /invalid request.*incorrect length/i,
				'category' => 'client'
			)
			expect( body ).to be_nil
		end


		it "send an error response if the request's header is not a Map" do
			sock.send( MessagePack.pack([nil, {}]) )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include(
				'success'  => false,
				'reason'   => /invalid request.*header is not a map/i,
				'category' => 'client'
			)
			expect( body ).to be_nil
		end

		it "send an error response if the request's body is not a Map or Nil" do
			sock.send( MessagePack.pack([{version: 1, action: 'list'}, 18]) )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include(
				'success'  => false,
				'reason'   => /invalid request.*body must be a map or nil/i,
				'category' => 'client'
			)
			expect( body ).to be_nil
		end


		it "send an error response if missing a version" do
			sock.send( MessagePack.pack([{action: 'list'}]) )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include(
				'success'  => false,
				'reason'   => /invalid request.*missing required header 'version'/i,
				'category' => 'client'
			)
			expect( body ).to be_nil
		end


		it "send an error response if missing an action" do
			sock.send( MessagePack.pack([{version: 1}]) )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include(
				'success'  => false,
				'reason'   => /invalid request.*missing required header 'action'/i,
				'category' => 'client'
			)
			expect( body ).to be_nil
		end


		it "send an error response for unknown actions" do
			badmsg = pack_message( :slap )
			sock.send( badmsg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include(
				'success'  => false,
				'reason'   => /invalid request.*no such action 'slap'/i,
				'category' => 'client'
			)
			expect( body ).to be_nil
		end
	end


	describe "status" do


		it "returns a Map describing the manager and its state" do
			msg = pack_message( :status )

			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => true )
			expect( body.length ).to eq( 4 )
			expect( body ).to include( 'server_version', 'state', 'uptime', 'nodecount' )
		end

	end


	describe "fetch", :skip do

		it "returns a list of serialized nodes matching specified criteria" do
			msg = pack_message( :fetch, type: 'service', port: 22 )

			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => true )
			expect( body.length ).to eq( manager.nodes.length )
		end


		it "returns a list of identifiers matching specified criteria" do
			msg = pack_message( :fetch, {return: nil}, type: 'service', port: 22 )

			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => true )
			expect( body.length ).to eq( manager.nodes.length )
		end


		it "returns a list of serialized node attributes matching specified criteria" do
			msg = pack_message( :fetch, {return: %w[status tags description]},
				type: 'service', port: 22 )

			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => true )
			expect( body.length ).to eq( manager.nodes.length )
		end

	end



	describe "list" do

		it "returns a list of node identifiers" do
			msg = pack_message( :list )
			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => true )
			expect( body['nodes'].length ).to eq( manager.nodes.length )
			expect( body['nodes'] ).to include( "_", "duir" )
		end

	end

end

