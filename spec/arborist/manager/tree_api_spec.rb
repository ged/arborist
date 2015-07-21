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
		while @manager.zmq_loop.running? || count > 30
			sleep 0.1
			Loggability[ Arborist ].info "ZMQ loop still running"
			count += 1
		end
		raise "ZMQ Loop didn't stop" if @manager.zmq_loop.running?
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


	describe "fetch" do

		it "returns an array of full state maps for nodes matching specified criteria" do
			msg = pack_message( :fetch, type: 'service', port: 22 )

			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => true )

			expect( body ).to be_a( Hash )
			expect( body.length ).to eq( 3 )

			expect( body.values ).to all( be_a(Hash) )
			expect( body.values ).to all( include('status', 'type') )
		end


		it "doesn't return nodes beneath downed nodes by default" do
			manager.nodes['sidonie'].update( error: 'sunspots' )
			msg = pack_message( :fetch, type: 'service', port: 22 )

			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => true )
			expect( body ).to be_a( Hash )
			expect( body.length ).to eq( 2 )
			expect( body ).to include( 'duir-ssh', 'yevaud-ssh' )
		end


		it "does return nodes beneath downed nodes if asked to" do
			manager.nodes['sidonie'].update( error: 'plague of locusts' )
			msg = pack_message( :fetch, {include_down: true}, type: 'service', port: 22 )

			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => true )
			expect( body ).to be_a( Hash )
			expect( body.length ).to eq( 3 )
			expect( body ).to include( 'duir-ssh', 'yevaud-ssh', 'sidonie-ssh' )
		end


		it "returns only identifiers if the `return` header is set to `nil`" do
			msg = pack_message( :fetch, {return: nil}, type: 'service', port: 22 )

			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => true )
			expect( body ).to be_a( Hash )
			expect( body.length ).to eq( 3 )
			expect( body ).to include( 'duir-ssh', 'yevaud-ssh', 'sidonie-ssh' )
			expect( body.values ).to all( be_empty )
		end


		it "returns only specified state if the `return` header is set to an Array of keys" do
			msg = pack_message( :fetch, {return: %w[status tags addresses]},
				type: 'service', port: 22 )

			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => true )
			expect( body.length ).to eq( 3 )
			expect( body ).to include( 'duir-ssh', 'yevaud-ssh', 'sidonie-ssh' )
			expect( body.values.map(&:keys) ).to all( contain_exactly('status', 'tags', 'addresses') )
		end

	end


	describe "list" do

		it "returns an array of node state" do
			msg = pack_message( :list )
			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => true )
			expect( body.length ).to eq( manager.nodes.length )
			expect( body ).to all( be_a(Hash) )
			expect( body ).to include( hash_including('identifier' => '_') )
			expect( body ).to include( hash_including('identifier' => 'duir') )
			expect( body ).to include( hash_including('identifier' => 'sidonie-ssh') )
			expect( body ).to include( hash_including('identifier' => 'sidonie-demon-http') )
			expect( body ).to include( hash_including('identifier' => 'yevaud') )
		end

	end


	describe "update" do

		it "merges the properties sent with those of the targeted nodes" do
			update_data = {
				duir: {
					ping: {
						rtt: 254
					}
				},
				sidonie: {
					ping: {
						rtt: 1208
					}
				},
				yevaud: {
					ping: {
						rtt: 843
					}
				}
			}
			msg = pack_message( :update, update_data )
			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => true )
			expect( body ).to be_nil

			expect( manager.nodes['duir'].properties['ping'] ).to include( 'rtt' => 254 )
			expect( manager.nodes['sidonie'].properties['ping'] ).to include( 'rtt' => 1208 )
			expect( manager.nodes['yevaud'].properties['ping'] ).to include( 'rtt' => 843 )
		end


		it "ignores unknown identifiers" do
			msg = pack_message( :update, charlie_humperton: {ping: { rtt: 8 }} )
			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => true )
		end

	end

end