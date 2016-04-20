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
		unless @manager_thread.join( 5 )
			$stderr.puts "Manager thread didn't exit on its own; killing it."
			@manager_thread.kill
		end

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


		it "send an error response if the request's body is not Nil, a Map, or an Array of Maps" do
			sock.send( MessagePack.pack([{version: 1, action: 'list'}, 18]) )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include(
				'success'  => false,
				'reason'   => /invalid request.*body must be nil, a map, or an array of maps/i,
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


		it "returns an array of full state maps for nodes not matching specified negative criteria" do
			msg = pack_message( :fetch, [ {}, {type: 'service', port: 22} ] )

			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => true )

			expect( body ).to be_a( Hash )
			expect( body.length ).to eq( manager.nodes.length - 3 )

			expect( body.values ).to all( be_a(Hash) )
			expect( body.values ).to all( include('status', 'type') )
		end


		it "returns an array of full state maps for nodes combining positive and negative criteria" do
			msg = pack_message( :fetch, [ {type: 'service'}, {port: 22} ] )

			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => true )

			expect( body ).to be_a( Hash )
			expect( body.length ).to eq( 16 )

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
			expect( body ).to include( hash_including('identifier' => 'sidonie') )
			expect( body ).to include( hash_including('identifier' => 'sidonie-ssh') )
			expect( body ).to include( hash_including('identifier' => 'sidonie-demon-http') )
			expect( body ).to include( hash_including('identifier' => 'yevaud') )
		end

		it "can be limited by depth" do
			msg = pack_message( :list, {depth: 1}, nil )
			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => true )
			expect( body.length ).to eq( 3 )
			expect( body ).to all( be_a(Hash) )
			expect( body ).to include( hash_including('identifier' => '_') )
			expect( body ).to include( hash_including('identifier' => 'duir') )
			expect( body ).to_not include( hash_including('identifier' => 'duir-ssh') )
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


	describe "subscribe" do

		it "adds a subscription for all event types to the root node by default" do
			criteria = {
				type: 'host'
			}

			msg = pack_message( :subscribe, criteria )

			resmsg = nil
			expect {
				sock.send( msg )
				resmsg = sock.recv
			}.to change { manager.subscriptions.length }.by( 1 ).and(
				change { manager.root.subscriptions.length }.by( 1 )
			)
			hdr, body = unpack_message( resmsg )

			sub_id = manager.subscriptions.keys.first

			expect( hdr ).to include( 'success' => true )
			expect( body ).to eq([ sub_id ])
		end


		it "adds a subscription to the specified node if an identifier is specified" do
			criteria = {
				type: 'host'
			}

			msg = pack_message( :subscribe, {identifier: 'sidonie'}, criteria )

			resmsg = nil
			expect {
				sock.send( msg )
				resmsg = sock.recv
			}.to change { manager.subscriptions.length }.by( 1 ).and(
				change { manager.nodes['sidonie'].subscriptions.length }.by( 1 )
			)
			hdr, body = unpack_message( resmsg )

			sub_id = manager.subscriptions.keys.first

			expect( hdr ).to include( 'success' => true )
			expect( body ).to eq([ sub_id ])
		end


		it "adds a subscription for node types matching a pattern if one is specified" do
			criteria = {
				type: 'host'
			}

			msg = pack_message( :subscribe, {event_type: 'node.ack'}, criteria )

			resmsg = nil
			expect {
				sock.send( msg )
				resmsg = sock.recv
			}.to change { manager.subscriptions.length }.by( 1 ).and(
				change { manager.root.subscriptions.length }.by( 1 )
			)
			hdr, body = unpack_message( resmsg )
			node = manager.subscriptions[ body.first ]
			sub = node.subscriptions[ body.first ]

			expect( sub.event_type ).to eq( 'node.ack' )
		end

	end


	describe "unsubscribe" do

		let( :subscription ) do
			manager.create_subscription( nil, 'node.delta', {type: 'host'} )
		end


		it "removes the subscription with the specified ID" do
			msg = pack_message( :unsubscribe, {subscription_id: subscription.id}, nil )

			resmsg = nil
			expect {
				sock.send( msg )
				resmsg = sock.recv
			}.to change { manager.subscriptions.length }.by( -1 ).and(
				change { manager.root.subscriptions.length }.by( -1 )
			)
			hdr, body = unpack_message( resmsg )

			expect( body ).to include( 'event_type' => 'node.delta', 'criteria' => {'type' => 'host'} )
		end


		it "ignores unsubscription of a non-existant ID" do
			msg = pack_message( :unsubscribe, {subscription_id: 'the bears!'}, nil )

			resmsg = nil
			expect {
				sock.send( msg )
				resmsg = sock.recv
			}.to_not change { manager.subscriptions.length }
			hdr, body = unpack_message( resmsg )

			expect( body ).to be_nil
		end

	end


	describe "prune" do

		it "removes a single node" do
			msg = pack_message( :prune, {identifier: 'duir-ssh'}, nil )
			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => true )
			expect( body ).to eq( true )
			expect( manager.nodes ).to_not include( 'duir-ssh' )
		end


		it "returns Nil without error if the node to prune didn't exist" do
			msg = pack_message( :prune, {identifier: 'shemp-ssh'}, nil )
			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => true )
			expect( body ).to be_nil
		end


		it "removes children nodes along with the parent" do
			msg = pack_message( :prune, {identifier: 'duir'}, nil )
			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => true )
			expect( body ).to eq( true )
			expect( manager.nodes ).to_not include( 'duir' )
			expect( manager.nodes ).to_not include( 'duir-ssh' )
		end


		it "returns an error to the client when missing required attributes" do
			msg = pack_message( :prune )
			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => false )
			expect( hdr['reason'] ).to match( /no identifier/i )
		end
	end


	describe "graft" do

		it "can add a node with no explicit parent" do
			header = {
				identifier: 'guenter',
		        type: 'host',
			}
			attributes = {
				description: 'The evil penguin node of doom.',
				addresses: ['10.2.66.8'],
				tags: ['internal', 'football']
			}
			msg = pack_message( :graft, header, attributes )

			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => true )
			expect( body ).to eq( 'guenter' )

			new_node = manager.nodes[ 'guenter' ]
			expect( new_node ).to be_a( Arborist::Node::Host )
			expect( new_node.identifier ).to eq( header[:identifier] )
			expect( new_node.description ).to eq( attributes[:description] )
			expect( new_node.addresses ).to eq([ IPAddr.new(attributes[:addresses].first) ])
			expect( new_node.tags ).to include( *attributes[:tags] )
		end


		it "can add a node with a parent specified" do
			header = {
				identifier: 'orgalorg',
		        type: 'host',
				parent: 'duir'
			}
			attributes = {
				description: 'The true form of the evil penguin node of doom.',
				addresses: ['192.168.22.8'],
				tags: ['evil', 'space', 'entity']
			}
			msg = pack_message( :graft, header, attributes )

			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => true )
			expect( body ).to eq( 'orgalorg' )

			new_node = manager.nodes[ 'orgalorg' ]
			expect( new_node ).to be_a( Arborist::Node::Host )
			expect( new_node.identifier ).to eq( header[:identifier] )
			expect( new_node.parent ).to eq( header[:parent] )
			expect( new_node.description ).to eq( attributes[:description] )
			expect( new_node.addresses ).to eq([ IPAddr.new(attributes[:addresses].first) ])
			expect( new_node.tags ).to include( *attributes[:tags] )
		end


		it "can add a subordinate node" do
			header = {
				identifier: 'echo',
		        type: 'service',
				parent: 'duir'
			}
			attributes = {
				description: 'Mmmmm AppleTalk.'
			}
			msg = pack_message( :graft, header, attributes )

			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => true )
			expect( body ).to eq( 'duir-echo' )

			new_node = manager.nodes[ 'duir-echo' ]
			expect( new_node ).to be_a( Arborist::Node::Service )
			expect( new_node.identifier ).to eq( 'duir-echo' )
			expect( new_node.parent ).to eq( header[:parent] )
			expect( new_node.description ).to eq( attributes[:description] )
			expect( new_node.port ).to eq( 7 )
			expect( new_node.protocol ).to eq( 'tcp' )
			expect( new_node.app_protocol ).to eq( 'echo' )
		end


		it "errors if adding a subordinate node with no parent" do
			header = {
				identifier: 'echo',
		        type: 'service'
			}
			attributes = {
				description: 'Mmmmm AppleTalk.'
			}
			msg = pack_message( :graft, header, attributes )

			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => false )
			expect( hdr['reason'] ).to match( /no host given/i )
		end

	end


	describe "modify" do

		it "can change operational attributes of a node" do
			header = {
				identifier: 'sidonie',
			}
			attributes = {
				parent: '_',
				addresses: ['192.168.32.32', '10.2.2.28']
			}
			msg = pack_message( :modify, header, attributes )

			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => true )

			node = manager.nodes[ 'sidonie' ]
			expect(
				node.addresses
			).to eq( [IPAddr.new('192.168.32.32'), IPAddr.new('10.2.2.28')] )
			expect( node.parent ).to eq( '_' )
		end


		it "ignores modifications to unsupported attributes" do
			header = {
				identifier: 'sidonie',
			}
			attributes = {
				identifier: 'somethingelse'
			}
			msg = pack_message( :modify, header, attributes )

			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => true )

			expect( manager.nodes['sidonie'] ).to be_an( Arborist::Node )
			expect( manager.nodes['sidonie'].identifier ).to eq( 'sidonie' )
		end


		it "errors on modifications to the root node" do
			header = {
				identifier: '_',
			}
			attributes = {
				identifier: 'somethingelse'
			}
			msg = pack_message( :modify, header, attributes )

			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => false )
			expect( manager.nodes['_'].identifier ).to eq( '_' )
		end


		it "errors on modifications to nonexistent nodes" do
			header = {
				identifier: 'nopenopenope',
			}
			attributes = {
				identifier: 'somethingelse'
			}
			msg = pack_message( :modify, header, attributes )

			sock.send( msg )
			resmsg = sock.recv

			hdr, body = unpack_message( resmsg )
			expect( hdr ).to include( 'success' => false )
		end
	end

end

