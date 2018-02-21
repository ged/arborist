#!/usr/bin/env rspec -cfd

require_relative '../spec_helper'

require 'tmpdir'
require 'timecop'
require 'arborist/manager'
require 'arborist/mixins'
require 'arborist/node/host'
require 'arborist/event/node_update'

using Arborist::TimeRefinements


describe Arborist::Manager do

	after( :all ) do
		Arborist::Manager.state_file = nil
	end
	before( :each ) do
		Arborist::Manager.configure
	end
	after( :each ) do
		Arborist::Node::Root.reset
	end


	let( :manager ) { described_class.new }
	let( :tmpfile_pathname ) { Pathname(Dir::Tmpname.create(['arb', 'tree']) {}) }


	#
	# Examples
	#

	it "starts with a root node" do
		expect( described_class.new.root ).to be_a( Arborist::Node )
	end


	it "starts with a node registry with the root node and itself" do
		result = manager.nodes
		expect( result ).to include( '_' )
		expect( result['_'] ).to be( manager.root )
	end


	it "knows how long it has been running" do
		Timecop.freeze do
			manager.start_time = Time.now

			Timecop.travel( 10 ) do
				expect( manager.uptime ).to be_within( 1 ).of( 10 )
			end
		end
	end


	it "has an uptime of 0 if it hasn't yet been started" do
		expect( manager.uptime ).to eq( 0 )
	end


	describe "state-saving" do

		before( :each ) do
			Arborist::Manager.state_file = nil
		end

		let( :router_node ) { Arborist::Host('router') }
		let( :host_node ) { Arborist::Host( 'host-a', router_node ) }
		let( :tree ) {[ router_node, host_node ]}

		let( :manager ) do
			instance = described_class.new
			instance.load_tree( tree )
			instance
		end


		it "saves the state of its node tree if the state file is configured" do
			statefile = Pathname( './arborist.tree' )
			Arborist::Manager.state_file = statefile

			tempfile = instance_double( Tempfile,
				path: './arborist20160224-31449-zevoz2.tree', unlink: nil )

			expect( Tempfile ).to receive( :create ).
				with( ['arborist', '.tree'], '.', encoding: 'binary' ).
				and_return( tempfile )
			expect( Marshal ).to receive( :dump ).with( manager.nodes, tempfile )
			expect( tempfile ).to receive( :close )
			expect( File ).to receive( :rename ).
				with( './arborist20160224-31449-zevoz2.tree', './arborist.tree' )

			manager.save_node_states
		end


		it "cleans up the tempfile created by checkpointing if renaming the file fails" do
			statefile = Pathname( './arborist.tree' )
			Arborist::Manager.state_file = statefile

			tempfile = instance_double( Tempfile, path: './arborist20160224-31449-zevoz2.tree' )

			expect( Tempfile ).to receive( :create ).
				with( ['arborist', '.tree'], '.', encoding: 'binary' ).
				and_return( tempfile )
			expect( Marshal ).to receive( :dump ).with( manager.nodes, tempfile )
			expect( tempfile ).to receive( :close )
			expect( File ).to receive( :rename ).
				and_raise( Errno::ENOENT.new("no such file or directory") )
			expect( File ).to receive( :exist? ).with( tempfile.path ).and_return( true )
			expect( File ).to receive( :unlink ).with( tempfile.path )

			manager.save_node_states
		end


		it "doesn't try to save state if the state file is not configured" do
			Arborist::Manager.state_file = nil

			expect( Tempfile ).to_not receive( :create )
			expect( Marshal ).to_not receive( :dump )
			expect( File ).to_not receive( :rename )

			manager.save_node_states
		end


		it "restores the state of loaded nodes if the state file is configured" do
			_ = manager

			Arborist::Manager.state_file = './arborist.tree'
			statefile = Arborist::Manager.state_file
			state_file_io = instance_double( File )

			saved_router_node = Marshal.load( Marshal.dump(router_node) )
			saved_router_node.instance_variable_set( :@status, 'up' )
			saved_host_node = Marshal.load( Marshal.dump(host_node) )
			saved_host_node.instance_variable_set( :@status, 'down' )
			saved_host_node.errors = { '_' => 'Stuff happened and it was not good.' }

			expect( statefile ).to receive( :readable? ).and_return( true )
			expect( statefile ).to receive( :open ).with( 'r:binary' ).
				and_return( state_file_io )
			expect( Marshal ).to receive( :load ).with( state_file_io ).
				and_return({ 'router' => saved_router_node, 'host-a' => saved_host_node })

			expect( manager.restore_node_states ).to be_truthy

			expect( manager.nodes['router'].status ).to eq( 'up' )
			expect( manager.nodes['host-a'].status ).to eq( 'down' )
			expect( manager.nodes['host-a'].errors ).to eq({ '_' => 'Stuff happened and it was not good.' })

		end


		it "doesn't error if the configured state file isn't readable" do
			_ = manager

			Arborist::Manager.state_file = './arborist.tree'

			expect( Arborist::Manager.state_file ).to receive( :readable? ).and_return( false )
			expect( Arborist::Manager.state_file ).to_not receive( :open )

			expect( manager.restore_node_states ).to be_falsey
		end


		it "checkpoints the state file periodically if an interval is configured" do
			statefile = tmpfile_pathname()
			described_class.configure( checkpoint_frequency: 20_000, state_file: statefile )

			manager = described_class.new
			manager.register_checkpoint_timer
			expect( manager.checkpoint_timer ).to be_a( Timers::Timer )
			expect( statefile ).to_not exist

			manager.checkpoint_timer.fire
			expect( statefile ).to exist
			states = Marshal.load( statefile.open('r:binary') )

			expect( states ).to be_a( Hash )
			expect( states.keys ).to eq( manager.nodes.keys )
		end


		it "doesn't checkpoint if no interval is configured" do
			described_class.configure( manager: {checkpoint_frequency: nil, state_file: 'arb.tree'} )

			manager = described_class.new
			expect( manager.checkpoint_timer ).to be_nil
		end


		it "doesn't checkpoint if no state file is configured" do
			described_class.configure( manager: {checkpoint_frequency: 20, state_file: nil} )

			manager = described_class.new
			expect( manager.checkpoint_timer ).to be_nil
		end


		it "writes a checkpoint if it receives a SIGUSR1"


	end


	context "heartbeat event" do

		it "errors if configured with a heartbeat of 0" do
			expect {
				described_class.configure( heartbeat_frequency: 0 )
			}.to raise_error( Arborist::ConfigError, /positive and non-zero/i )
		end


		it "is sent at the configured interval" do
			described_class.configure( heartbeat_frequency: 11 )
			expect( manager.reactor ).to receive( :add_periodic_timer ).with( 11 )

			manager.register_heartbeat_timer
		end


		it "doesn't try to publish the heartbeat if it's not been started" do
			manager.start_time = nil

			manager.publish_heartbeat_event
			expect( manager.event_queue ).to be_empty
		end


		it "contains runtime information about the manager" do
			time = Time.now
			manager.start_time = time

			manager.publish_heartbeat_event
			event = manager.event_queue.shift

			expect( event ).to be_a( CZTop::Message )
			decoded = Arborist::EventAPI.decode( event )

			expect( decoded ).to include(
				'run_id' => manager.run_id,
				'start_time' => time.iso8601,
				'version' => Arborist::VERSION
			)
		end

	end


	context "a new empty manager" do

		let( :node ) do
			testing_node 'italian_lessons'
		end
		let( :node2 ) do
			testing_node 'french_laundry'
		end
		let( :node3 ) do
			testing_node 'german_oak_cats'
		end


		it "has a nodecount of 1" do
			expect( manager.nodecount ).to eq( 1 )
		end


		it "can have a node added to it" do
			manager.add_node( node )
			expect( manager.nodes ).to include( 'italian_lessons' )
			expect( manager.nodes['italian_lessons'] ).to be( node )
			expect( manager.nodecount ).to eq( 2 )
			expect( manager.nodelist ).to include( '_', 'italian_lessons' )
		end


		it "can load its tree from an Enumerator that yields nodes" do
			manager.load_tree([ node, node2, node3 ])
			expect( manager.nodes ).to include( 'italian_lessons', 'french_laundry', 'german_oak_cats' )
			expect( manager.nodes['italian_lessons'] ).to be( node )
			expect( manager.nodes['french_laundry'] ).to be( node2 )
			expect( manager.nodes['german_oak_cats'] ).to be( node3 )
			expect( manager.nodecount ).to eq( 4 )
			expect( manager.nodelist ).to include(
				'_', 'italian_lessons', 'french_laundry', 'german_oak_cats'
			)
		end


		it "can replace an existing node" do
			manager.add_node( node )
			another_node = testing_node( 'italian_lessons' )
			manager.add_node( another_node )

			expect( manager.nodes ).to include( 'italian_lessons' )
			expect( manager.nodes['italian_lessons'] ).to_not be( node )
			expect( manager.nodes['italian_lessons'] ).to be( another_node )

			expect( manager.nodecount ).to eq( 2 )
			expect( manager.nodelist ).to include( '_', 'italian_lessons' )
		end


		it "can have a node removed from it" do
			manager.add_node( node )
			deleted_node = manager.remove_node( 'italian_lessons' )

			expect( deleted_node ).to be( node )
			expect( manager.nodes ).to_not include( 'italian_lessons' )

			expect( manager.nodecount ).to eq( 1 )
			expect( manager.nodelist ).to include( '_' )
		end


		it "disallows removal of operational nodes" do
			expect {
				manager.remove_node('_')
			}.to raise_error( /can't remove an operational node/i )
		end

	end


	context "a manager with some loaded nodes" do

		let( :trunk_node ) do
			testing_node( 'trunk' )
		end
		let( :branch_node ) do
			testing_node( 'branch', 'trunk' )
		end
		let( :leaf_node ) do
			testing_node( 'leaf', 'branch' )
		end

		let( :manager ) do
			instance = described_class.new
			instance.load_tree([ branch_node, leaf_node, trunk_node ])
			instance
		end


		it "has a tree built out of its nodes" do
			expect( manager.root ).to have_children
		end


		it "knows what nodes have been loaded" do
			expect( manager.nodelist ).to include( 'trunk', 'branch', 'leaf' )
		end


		it "errors if any of its nodes are missing their parent" do
			manager = described_class.new
			orphan = testing_node( 'orphan' ) do
				parent 'daddy_warbucks'
			end

			expect {
				manager.load_tree([ orphan ])
			}.to raise_error( /no parent 'daddy_warbucks' node loaded for/i )
		end


		it "grafts a node into the tree when one with a previously unknown identifier is added" do
			new_node = testing_node( 'new' ) do
				parent 'branch'
			end

			manager.add_node( new_node )
			expect( manager.nodes['branch'].children ).to include( 'new' )
		end


		it "replaces a node in the tree when a node with an existing identifier is added" do
			updated_node = testing_node( 'leaf' ) do
				parent 'trunk'
			end

			manager.add_node( updated_node )
			expect( manager.nodes['branch'].children ).to_not include( 'leaf' => leaf_node )
			expect( manager.nodes['trunk'].children ).to include( 'leaf' => updated_node )
		end


		it "rebuilds the tree when a node is removed from it" do
			manager.remove_node( 'branch' )

			expect( manager.nodes['trunk'].children ).to_not include( 'branch' )
			expect( manager.nodes ).to_not include( 'branch' )
			expect( manager.nodes ).to_not include( 'leaf' )
		end

	end


	describe "tree API", :testing_manager do

		before( :each ) do
			@manager = nil
			@manager_thread = Thread.new do
				@manager = make_testing_manager()
				Thread.current.abort_on_exception = true
				@manager.run
				Loggability[ Arborist ].info "Stopped the test manager"
			end

			count = 0
			until (@manager && @manager.running?) || count > 30
				sleep 0.1
				count += 1
			end
			raise "Manager didn't start up" unless @manager.running?
		end

		after( :each ) do
			@manager.simulate_signal( :TERM )
			unless @manager_thread.join( 5 )
				$stderr.puts "Manager thread didn't exit on its own; killing it."
				@manager_thread.kill
			end

			count = 0
			while @manager.running? || count > 30
				sleep 0.1
				Loggability[ Arborist ].info "Manager still running"
				count += 1
			end
			raise "Manager didn't stop" if @manager.running?
		end


		let( :manager ) { @manager }

		let( :sock ) do
			sock = CZTop::Socket::REQ.new
			sock.options.linger = 0
			sock.connect( TESTING_API_SOCK )
			sock
		end


		describe "status" do

			it "returns a Map describing the manager and its state" do
				msg = Arborist::TreeAPI.request( :status )

				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include( 'success' => true )
				expect( body.length ).to eq( 4 )
				expect( body ).to include( 'server_version', 'state', 'uptime', 'nodecount' )
			end

		end


		describe "search" do

			it "returns an array of full state maps for nodes matching specified criteria" do
				msg = Arborist::TreeAPI.request( :search, type: 'service', port: 22 )

				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include( 'success' => true )

				expect( body ).to be_a( Hash )
				expect( body.length ).to eq( 3 )

				expect( body.values ).to all( be_a(Hash) )
				expect( body.values ).to all( include('status', 'type') )
			end


			it "returns an array of full state maps for nodes not matching specified negative criteria" do
				msg = Arborist::TreeAPI.request( :search, [ {}, {type: 'service', port: 22} ] )

				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include( 'success' => true )

				expect( body ).to be_a( Hash )
				expect( body.length ).to eq( manager.nodes.length - 3 )

				expect( body.values ).to all( be_a(Hash) )
				expect( body.values ).to all( include('status', 'type') )
			end


			it "returns an array of full state maps for nodes combining positive and negative criteria" do
				msg = Arborist::TreeAPI.request( :search, [ {type: 'service'}, {port: 22} ] )

				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include( 'success' => true )

				expect( body ).to be_a( Hash )
				expect( body.length ).to eq( 16 )

				expect( body.values ).to all( be_a(Hash) )
				expect( body.values ).to all( include('status', 'type') )
			end


			it "doesn't return nodes beneath downed nodes by default" do
				manager.nodes['sidonie'].update( error: 'sunspots' )
				msg = Arborist::TreeAPI.request( :search, type: 'service', port: 22 )

				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include( 'success' => true )
				expect( body ).to be_a( Hash )
				expect( body.length ).to eq( 2 )
				expect( body ).to include( 'duir-ssh', 'yevaud-ssh' )
			end


			it "does return nodes beneath downed nodes if asked to" do
				manager.nodes['sidonie'].update( error: 'plague of locusts' )
				msg = Arborist::TreeAPI.request( :search, {include_down: true}, type: 'service', port: 22 )

				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include( 'success' => true )
				expect( body ).to be_a( Hash )
				expect( body.length ).to eq( 3 )
				expect( body ).to include( 'duir-ssh', 'yevaud-ssh', 'sidonie-ssh' )
			end


			it "returns only identifiers if the `return` header is set to `nil`" do
				msg = Arborist::TreeAPI.request( :search, {return: nil}, type: 'service', port: 22 )

				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include( 'success' => true )
				expect( body ).to be_a( Hash )
				expect( body.length ).to eq( 3 )
				expect( body ).to include( 'duir-ssh', 'yevaud-ssh', 'sidonie-ssh' )
				expect( body.values ).to all( be_empty )
			end


			it "returns only specified state if the `return` header is set to an Array of keys" do
				msg = Arborist::TreeAPI.request( :search, {return: %w[status tags addresses]},
					type: 'service', port: 22 )

				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include( 'success' => true )
				expect( body.length ).to eq( 3 )
				expect( body ).to include( 'duir-ssh', 'yevaud-ssh', 'sidonie-ssh' )
				expect( body.values.map(&:keys) ).to all( contain_exactly('status', 'tags', 'addresses') )
			end


		end


		describe "fetch" do

			it "returns an array of node state" do
				msg = Arborist::TreeAPI.request( :fetch )
				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
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


			it "can start at a node other than the root" do
				msg = Arborist::TreeAPI.request( :fetch, {from: 'sidonie'}, nil )
				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include( 'success' => true )
				expect( body.length ).to eq( manager.nodes.keys.count {|id| id.include?('sidonie')} )
				expect( body ).to all( be_a(Hash) )
				expect( body ).to_not include( hash_including('identifier' => '_') )
				expect( body ).to_not include( hash_including('identifier' => 'duir') )
				expect( body ).to include( hash_including('identifier' => 'sidonie') )
				expect( body ).to include( hash_including('identifier' => 'sidonie-ssh') )
				expect( body ).to include( hash_including('identifier' => 'sidonie-demon-http') )
				expect( body ).to_not include( hash_including('identifier' => 'yevaud') )
			end


			it "can be fetched as a tree" do
				msg = Arborist::TreeAPI.request( :fetch, {tree: true}, nil )
				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include( 'success' => true )
				expect( body.length ).to eq( 1 )
				expect( body.first ).to be_a( Hash )
				expect( body.first ).to include( 'children' )
				expect( body.first['identifier'] ).to eq( '_' )
				expect( body.first['children'].keys ).to include( 'duir', 'localhost' )
			end


			it "can be limited by depth" do
				msg = Arborist::TreeAPI.request( :fetch, {depth: 1}, nil )
				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include( 'success' => true )
				expect( body.length ).to eq( 3 )
				expect( body ).to all( be_a(Hash) )
				expect( body ).to include( hash_including('identifier' => '_') )
				expect( body ).to include( hash_including('identifier' => 'duir') )
				expect( body ).to_not include( hash_including('identifier' => 'duir-ssh') )
			end


			it "errors when fetching from a nonexistent node" do
				msg = Arborist::TreeAPI.request( :fetch, {from: "nope-nope-nope"}, nil )
				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include( 'success' => false )
				expect( hdr ).to include( "reason" => "No such node nope-nope-nope." )
				expect( body ).to be_nil
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
				msg = Arborist::TreeAPI.request( :update, update_data )
				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include( 'success' => true )
				expect( body ).to be_nil

				expect( manager.nodes['duir'].properties['ping'] ).to include( 'rtt' => 254 )
				expect( manager.nodes['sidonie'].properties['ping'] ).to include( 'rtt' => 1208 )
				expect( manager.nodes['yevaud'].properties['ping'] ).to include( 'rtt' => 843 )
			end


			it "ignores unknown identifiers" do
				msg = Arborist::TreeAPI.request( :update, charlie_humperton: {ping: { rtt: 8 }} )
				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include( 'success' => true )
			end

			it "fails with a client error if the body is invalid" do
				msg = Arborist::TreeAPI.request( :update, nil )
				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include( 'success' => false )
				expect( hdr['reason'] ).to match( /respond to #each/ )
			end
		end


		describe "subscribe" do

			it "adds a subscription for all event types to the root node by default" do
				msg = Arborist::TreeAPI.request( :subscribe, [{}, {}] )

				resmsg = nil
				expect {
					msg.send_to( sock )
					resmsg = sock.receive
				}.to change { manager.subscriptions.length }.by( 1 ).and(
					change { manager.root.subscriptions.length }.by( 1 )
				)
				hdr, body = Arborist::TreeAPI.decode( resmsg )

				sub_id = manager.subscriptions.keys.first

				expect( hdr ).to include( 'success' => true )
				expect( body ).to be_a( Hash )
				expect( body ).to include( 'id' )
				expect( manager.subscriptions.keys ).to include( body['id'] )
			end


			it "adds a subscription to the specified node if an identifier is specified" do
				msg = Arborist::TreeAPI.request( :subscribe, {identifier: 'sidonie'}, [{}, {}] )

				resmsg = nil
				expect {
					msg.send_to( sock )
					resmsg = sock.receive
				}.to change { manager.subscriptions.length }.by( 1 ).and(
					change { manager.nodes['sidonie'].subscriptions.length }.by( 1 )
				)
				hdr, body = Arborist::TreeAPI.decode( resmsg )

				expect( hdr ).to include( 'success' => true )
				expect( body ).to be_a( Hash )
				expect( body ).to include( 'id' )
				expect( manager.subscriptions.keys ).to include( body['id'] )
			end


			it "adds a subscription for particular event types if one is specified" do
				msg = Arborist::TreeAPI.request( :subscribe, {event_type: 'node.acked'}, [{}, {}] )

				resmsg = nil
				expect {
					msg.send_to( sock )
					resmsg = sock.receive
				}.to change { manager.subscriptions.length }.by( 1 ).and(
					change { manager.root.subscriptions.length }.by( 1 )
				)
				hdr, body = Arborist::TreeAPI.decode( resmsg )
				node = manager.subscriptions[ body['id'] ]
				sub = node.subscriptions[ body['id'] ]

				expect( sub.event_type ).to eq( 'node.acked' )
			end


			it "adds a subscription for events which match a pattern if one is specified" do
				criteria = { type: 'host' }

				msg = Arborist::TreeAPI.request( :subscribe, [criteria, {}] )

				resmsg = nil
				expect {
					msg.send_to( sock )
					resmsg = sock.receive
				}.to change { manager.subscriptions.length }.by( 1 ).and(
					change { manager.root.subscriptions.length }.by( 1 )
				)
				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( body ).to be_a( Hash ).and( include('id') )
				node = manager.subscriptions[ body['id'] ]
				sub = node.subscriptions[ body['id'] ]

				expect( sub.event_type ).to be_nil
				expect( sub.criteria ).to eq({ 'type' => 'host' })
			end


			it "adds a subscription for events which don't match a pattern if an exclusion pattern is given" do
				criteria = { type: 'host' }

				msg = Arborist::TreeAPI.request( :subscribe, [{}, criteria] )

				resmsg = nil
				expect {
					msg.send_to( sock )
					resmsg = sock.receive
				}.to change { manager.subscriptions.length }.by( 1 ).and(
					change { manager.root.subscriptions.length }.by( 1 )
				)
				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( body ).to be_a( Hash ).and( include('id') )
				node = manager.subscriptions[ body['id'] ]
				sub = node.subscriptions[ body['id'] ]

				expect( sub.event_type ).to be_nil
				expect( sub.negative_criteria ).to eq({ 'type' => 'host' })
			end

		end


		describe "unsubscribe" do

			let( :subscription ) do
				manager.create_subscription( nil, 'node.delta', {type: 'host'} )
			end


			it "removes the subscription with the specified ID" do
				msg = Arborist::TreeAPI.request( :unsubscribe, {subscription_id: subscription.id}, nil )

				resmsg = nil
				expect {
					msg.send_to( sock )
					resmsg = sock.receive
				}.to change { manager.subscriptions.length }.by( -1 ).and(
					change { manager.root.subscriptions.length }.by( -1 )
				)
				hdr, body = Arborist::TreeAPI.decode( resmsg )

				expect( body ).to include( 'event_type' => 'node.delta', 'criteria' => {'type' => 'host'} )
			end


			it "ignores unsubscription of a non-existant ID" do
				msg = Arborist::TreeAPI.request( :unsubscribe, {subscription_id: 'the bears!'}, nil )

				resmsg = nil
				expect {
					msg.send_to( sock )
					resmsg = sock.receive
				}.to_not change { manager.subscriptions.length }
				hdr, body = Arborist::TreeAPI.decode( resmsg )

				expect( body ).to be_nil
			end

		end


		describe "prune" do

			it "removes a single node" do
				msg = Arborist::TreeAPI.request( :prune, {identifier: 'duir-ssh'}, nil )
				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include( 'success' => true )
				expect( body ).to be_a( Hash )
				expect( body ).to include( 'identifier' => 'duir-ssh' )
				expect( manager.nodes ).to_not include( 'duir-ssh' )
			end


			it "returns Nil without error if the node to prune didn't exist" do
				msg = Arborist::TreeAPI.request( :prune, {identifier: 'shemp-ssh'}, nil )
				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include( 'success' => true )
				expect( body ).to be_nil
			end


			it "removes children nodes along with the parent" do
				msg = Arborist::TreeAPI.request( :prune, {identifier: 'duir'}, nil )
				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include( 'success' => true )
				expect( body ).to be_a( Hash )
				expect( body ).to include( 'identifier' => 'duir' )
				expect( manager.nodes ).to_not include( 'duir' )
				expect( manager.nodes ).to_not include( 'duir-ssh' )
			end


			it "returns an error to the client when missing required attributes" do
				msg = Arborist::TreeAPI.request( :prune )
				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
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
				msg = Arborist::TreeAPI.request( :graft, header, attributes )

				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include( 'success' => true )
				expect( body ).to include( 'identifier' => 'guenter' )

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
				msg = Arborist::TreeAPI.request( :graft, header, attributes )

				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include( 'success' => true )
				expect( body ).to include( 'identifier' => 'orgalorg' )

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
				msg = Arborist::TreeAPI.request( :graft, header, attributes )

				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include( 'success' => true )
				expect( body ).to eq( 'identifier' => 'duir-echo' )

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
				msg = Arborist::TreeAPI.request( :graft, header, attributes )

				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include( 'success' => false )
				expect( hdr['reason'] ).to match( /no host given/i )
			end


			it "errors if adding a node that already exists" do
				header = {
					identifier: 'duir',
			        type: 'host',
				}
				msg = Arborist::TreeAPI.request( :graft, header, {} )

				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include( 'success' => false )
				expect( hdr['reason'] ).to match( /exists/i )
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
				msg = Arborist::TreeAPI.request( :modify, header, attributes )

				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
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
				msg = Arborist::TreeAPI.request( :modify, header, attributes )

				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
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
				msg = Arborist::TreeAPI.request( :modify, header, attributes )

				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
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
				msg = Arborist::TreeAPI.request( :modify, header, attributes )

				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include( 'success' => false )
			end


			it "reparents a node whose parent is altered" do
				header = {
					identifier: 'sidonie'
				}
				attributes = {
					parent: 'yevaud'
				}

				msg = Arborist::TreeAPI.request( :modify, header, attributes )

				node = manager.nodes[ 'sidonie' ]
				old_parent = manager.nodes[ 'duir' ]
				expect( node.parent ).to eq( 'duir' )

				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include( 'success' => true )

				new_parent = manager.nodes[ 'yevaud' ]
				expect( node.parent ).to eq( 'yevaud' )
				expect( old_parent.children ).to_not include( 'sidonie' )
				expect( new_parent.children ).to include( 'sidonie' )
			end
		end


		describe "deps" do

			it "returns a list of the identifiers of nodes that depend on it" do
				msg = Arborist::TreeAPI.request( :deps, {from: 'sidonie'}, nil )
				msg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include( 'success' => true )
				expect( body ).to be_a( Hash )
				expect( body ).to include( 'deps' )
				expect( body['deps'] ).to be_an( Array ).and( include('yevaud-cozy_frontend') )
			end

		end


		describe "malformed requests" do

			it "send an error response if the request can't be deserialized" do
				sock << "whatevs, dude!"
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include(
					'success'  => false,
					'reason'   => /invalid message/i,
					'category' => 'client'
				)
				expect( body ).to be_nil
			end


			it "send an error response if the request isn't a tuple" do
				sock << MessagePack.pack({ version: 1, action: 'fetch' })
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include(
					'success'  => false,
					'reason'   => /invalid message.*not an array/i,
					'category' => 'client'
				)
				expect( body ).to be_nil
			end


			it "send an error response if the request is empty" do
				sock << MessagePack.pack([])
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include(
					'success'  => false,
					'reason'   => /invalid message.*expected 1-2 parts, got 0/i,
					'category' => 'client'
				)
				expect( body ).to be_nil
			end


			it "send an error response if the request is an incorrect length" do
				sock << MessagePack.pack( [{}, {}, {}] )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include(
					'success'  => false,
					'reason'   => /expected 1-2 parts, got 3/i,
					'category' => 'client'
				)
				expect( body ).to be_nil
			end


			it "send an error response if the request's header is not a Map" do
				sock << MessagePack.pack( [nil, {}] )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include(
					'success'  => false,
					'reason'   => /no header/i,
					'category' => 'client'
				)
				expect( body ).to be_nil
			end


			it "send an error response if the request's body is not Nil, a Map, or an Array of Maps" do
				sock << MessagePack.pack( [{version: 1, action: 'fetch'}, 18] )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include(
					'success'  => false,
					'reason'   => /invalid message.*body must be nil, a map, or an array of maps/i,
					'category' => 'client'
				)
				expect( body ).to be_nil
			end


			it "send an error response if missing a version" do
				sock << MessagePack.pack( [{action: 'fetch'}] )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include(
					'success'  => false,
					'reason'   => /invalid message.*missing required header 'version'/i,
					'category' => 'client'
				)
				expect( body ).to be_nil
			end


			it "send an error response if missing an action" do
				sock << MessagePack.pack( [{version: 1}] )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include(
					'success'  => false,
					'reason'   => /invalid message.*missing required header 'action'/i,
					'category' => 'client'
				)
				expect( body ).to be_nil
			end


			it "send an error response for unknown actions" do
				badmsg = Arborist::TreeAPI.request( :slap )
				badmsg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include(
					'success'  => false,
					'reason'   => /invalid message.*no such action 'slap'/i,
					'category' => 'client'
				)
				expect( body ).to be_nil
			end


			it "send an error response for the `tree` action" do
				badmsg = Arborist::TreeAPI.request( :tree )
				badmsg.send_to( sock )
				resmsg = sock.receive

				hdr, body = Arborist::TreeAPI.decode( resmsg )
				expect( hdr ).to include(
					'success'  => false,
					'reason'   => /invalid message.*no such action 'tree'/i,
					'category' => 'client'
				)
				expect( body ).to be_nil
			end

		end

	end


	describe "event API" do

		before( :each ) do
			@manager = nil
			@manager_thread = Thread.new do
				@manager = make_testing_manager()
				Thread.current.abort_on_exception = true
				@manager.run
				Loggability[ Arborist ].info "Stopped the test manager"
			end

			count = 0
			until (@manager && @manager.running?) || count > 30
				sleep 0.1
				count += 1
			end
			raise "Manager didn't start up" unless @manager.running?
		end

		after( :each ) do
			@manager.simulate_signal( :TERM )
			unless @manager_thread.join( 5 )
				$stderr.puts "Manager thread didn't exit on its own; killing it."
				@manager_thread.kill
			end

			count = 0
			while @manager.running? || count > 30
				sleep 0.1
				Loggability[ Arborist ].info "Manager still running"
				count += 1
			end
			raise "Manager didn't stop" if @manager.running?
		end


		let( :manager ) { @manager }

		let!( :sock ) do
			sock = CZTop::Socket::SUB.new
			sock.options.linger = 0
			sock.subscribe( '' )
			event_uri = manager.event_socket.last_endpoint
			sock.connect( event_uri )
			Loggability[ Arborist ].info "Connected subscribed socket to %p" % [ event_uri ]
			sock
		end


		it "publishes messages via the event socket" do
			node = Arborist::Node.create( :root )
			event = Arborist::Event.create( :node_update, node )
			manager.publish( 'identifier-00aa', event )

			msg = nil
			wait( 1.second ).for { msg = sock.receive }.to be_a( CZTop::Message )

			expect( msg.frames.first.to_s ).to eq( 'identifier-00aa' )
			expect( msg.frames.last.to_s ).to be_a_messagepacked( Hash )
		end

	end


	describe "tree traversal" do

		let( :tree ) do
			#                        router
			# host_a                 host_b              host_c
			# www smtp imap          www nfs ssh         www

			[
				testing_node( 'router' ),
					testing_node( 'host-a', 'router' ),
						testing_node( 'host-a-www', 'host-a' ),
						testing_node( 'host-a-smtp', 'host-a' ),
						testing_node( 'host-a-imap', 'host-a' ),
					testing_node( 'host-b', 'router' ),
						testing_node( 'host-b-www', 'host-b' ),
						testing_node( 'host-b-nfs', 'host-b' ),
						testing_node( 'host-b-ssh', 'host-b' ),
					testing_node( 'host-c', 'router' ),
						testing_node( 'host-c-www', 'host-c' ),
					testing_node( 'host-d', 'router' ),
						testing_node( 'host-d-ssh', 'host-d' ),
						testing_node( 'host-d-amqp', 'host-d' ),
						testing_node( 'host-d-database', 'host-d' ),
						testing_node( 'host-d-memcached', 'host-d' ),
			]
		end

		let( :manager ) do
			instance = described_class.new
			instance.load_tree( tree )
			instance
		end


		it "can traverse all nodes in its node tree" do
			iter = manager.all_nodes
			expect( iter ).to be_a( Enumerator )
			expect( iter.to_a ).to eq( [manager.root] + tree )
		end


		it "can traverse all nodes whose status is 'up'" do
			manager.nodes.each {|_, node| node.status = 'up' }
			manager.nodes[ 'host-a' ].status = 'down'
			manager.nodes[ 'host-c' ].status = 'down'
			manager.nodes[ 'host-b-nfs' ].status = 'disabled'
			manager.nodes[ 'host-b-www' ].status = 'quieted'

			iter = manager.reachable_nodes

			expect( iter ).to be_a( Enumerator )

			nodes = iter.map( &:identifier )
			expect( nodes ).to include(
				"_",
				"router",
				"host-b",
				"host-b-ssh",
				"host-d",
				"host-d-ssh",
				"host-d-amqp",
				"host-d-database",
				"host-d-memcached",
			)
			expect( nodes ).to_not include(
				"host-b-www",
				"host-b-nfs",
				"host-c",
				"host-c-www",
				"host-a",
				"host-a-www",
				"host-a-smtp",
				"host-a-imap",
			)
		end


		it "can create an Enumerator for all of its children to a specified depth" do
			nodes = manager.depth_limited_enumerator_for( manager.nodes['_'], 2 ).to_a
			expect( nodes.length ).to eq( 6 )
			expect( nodes.map(&:identifier) ).to eq( %w[_ router host-a host-b host-c host-d] )
		end

	end


	describe "node updates and events" do

		let( :tree ) do
			#                        router
			# host_a                 host_b              host_c
			# www smtp imap          www nfs ssh         www

			[
				testing_node( 'router' ),
					testing_node( 'host-a', 'router' ),
						testing_node( 'host-a-www', 'host-a' ) { tags :home, :church },
						testing_node( 'host-a-smtp', 'host-a' ) { tags :home },
						testing_node( 'host-a-imap', 'host-a' ),
					testing_node( 'host-b', 'router' ),
						testing_node( 'host-b-www', 'host-b' ) { tags :church },
						testing_node( 'host-b-nfs', 'host-b' ),
						testing_node( 'host-b-ssh', 'host-b' ) { tags :work },
					testing_node( 'host-c', 'router' ),
						testing_node( 'host-c-www', 'host-c' ) { tags :work, :home },
			]
		end

		let( :manager ) do
			instance = described_class.new
			instance.load_tree( tree )
			instance
		end


		it "can search a Hash of node states" do
			states = manager.find_matching_node_states( {}, [] )
			expect( states.size ).to eq( manager.nodes.size )
			expect( states ).to include( 'host-b-nfs', 'host-c', 'router' )
			expect( states['host-b-nfs'] ).to be_a( Hash )
			expect( states['host-c'] ).to be_a( Hash )
			expect( states['router'] ).to be_a( Hash )
		end


		it "can search a Hash of node states for nodes which match specified criteria" do
			states = manager.find_matching_node_states( {'identifier' => 'host-c'}, [] )
			expect( states.size ).to eq( 1 )
			expect( states.keys.first ).to eq( 'host-c' )
			expect( states['host-c'] ).to be_a( Hash )
		end


		it "can search a Hash of node states for nodes which don't match specified negative criteria" do
			states = manager.find_matching_node_states( {}, [], false, {'identifier' => 'host-c'} )
			expect( states.size ).to eq( manager.nodes.size - 1 )
			expect( states ).to_not include( 'host-c' )
		end


		it "can search a Hash of node states for nodes combining positive and negative criteria" do
			positive = {'tag' => 'home'}
			negative = {'identifier' => 'host-a-www'}

			states = manager.find_matching_node_states( positive, [], false, negative )

			expect( states.size ).to eq( 2 )
			expect( states ).to_not include( 'host-a-www' )
		end


		it "can update an event by identifier" do
			manager.update_node( 'host-b-www', http: { status: 200 } )
			expect(
				manager.nodes['host-b-www'].properties
			).to include( 'http' => { 'status' => 200 } )
		end


		it "ignores updates to an identifier that is not (any longer) in the tree" do
			expect {
				manager.update_node( 'host-y', asset_tag: '2by-n86y7t' )
			}.to_not raise_error
		end


		it "propagates events from an update up the node tree" do
			expect( manager.root ).to receive( :publish_events ).
				at_least( :once ).
				and_call_original
			expect( manager.nodes['host-c'] ).to receive( :publish_events ).
				at_least( :once ).
				and_call_original
			manager.update_node( 'host-c-www', response_status: 504, error: 'Timeout talking to web service.' )
		end


		it "only propagates events to a node's ancestors" do
			expect( manager.root ).to receive( :publish_events ).
				at_least( :once ).
				and_call_original
			expect( manager.nodes['host-c'] ).to_not receive( :publish_events )

			manager.update_node( 'host-b-www', response_status: 504, error: 'Timeout talking to web service.' )
		end

	end


	describe "subscriptions" do

		let( :tree ) {[ testing_node('host-c') ]}
		let( :manager ) do
			instance = described_class.new
			instance.load_tree( tree )
			instance
		end


		it "can attach subscriptions to a node by its identifier" do
			sub = subid = nil
			expect {
				sub = manager.create_subscription( 'host-c', 'node.update', type: 'host' )
			}.to change { manager.subscriptions.size }.by( 1 )

			node = manager.subscriptions[ sub.id ]

			expect( sub ).to be_a( Arborist::Subscription )
			expect( node ).to be( manager.nodes['host-c'] )
		end


		it "can detach subscriptions from a node given the subscription ID" do
			sub = manager.create_subscription( 'host-c', 'node.ack', type: 'service' )
			rval = nil

			expect {
				rval = manager.remove_subscription( sub.id )
			}.to change { manager.subscriptions.size }.by( -1 ).and(
				change { manager.nodes['host-c'].subscriptions.size }.by( -1 )
			)

			expect( rval ).to be( sub )
		end

	end


end


