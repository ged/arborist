#!/usr/bin/env rspec -cfd

require_relative '../spec_helper'

require 'timecop'
require 'arborist/manager'
require 'arborist/node/host'

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
		let( :host_node ) { Arborist::Host( 'host_a', router_node ) }
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

			statefile = Pathname( './arborist.tree' )
			Arborist::Manager.state_file = statefile
			state_file_io = instance_double( File )

			saved_router_node = Marshal.load( Marshal.dump(router_node) )
			saved_router_node.instance_variable_set( :@status, 'up' )
			saved_host_node = Marshal.load( Marshal.dump(host_node) )
			saved_host_node.instance_variable_set( :@status, 'down' )
			saved_host_node.error = 'Stuff happened and it was not good.'

			expect( statefile ).to receive( :readable? ).and_return( true )
			expect( statefile ).to receive( :open ).with( 'r:binary' ).
				and_return( state_file_io )
			expect( Marshal ).to receive( :load ).with( state_file_io ).
				and_return({ 'router' => saved_router_node, 'host_a' => saved_host_node })

			expect( manager.restore_node_states ).to be_truthy

			expect( manager.nodes['router'].status ).to eq( 'up' )
			expect( manager.nodes['host_a'].status ).to eq( 'down' )
			expect( manager.nodes['host_a'].error ).to eq( 'Stuff happened and it was not good.' )

		end


		it "doesn't error if the configured state file isn't readable" do
			_ = manager

			statefile = Pathname( './arborist.tree' )
			Arborist::Manager.state_file = statefile

			expect( statefile ).to receive( :readable? ).and_return( false )
			expect( statefile ).to_not receive( :open )

			expect( manager.restore_node_states ).to be_falsey
		end


		it "checkpoints the state file periodically if an interval is configured" do
			described_class.configure( manager: {checkpoint_frequency: 20, state_file: 'arb.tree'} )

			timer = instance_double( ZMQ::Timer, "checkpoint timer" )
			expect( ZMQ::Timer ).to receive( :new ).with( 20, 0 ).and_return( timer )

			expect( manager.start_state_checkpointing ).to eq( timer )
		end


		it "doesn't checkpoint if no interval is configured" do
			described_class.configure( manager: {checkpoint_frequency: nil, state_file: 'arb.tree'} )

			expect( ZMQ::Timer ).to_not receive( :new )

			expect( manager.start_state_checkpointing ).to be_nil
		end


		it "doesn't checkpoint if no state file is configured" do
			described_class.configure( manager: {checkpoint_frequency: 20, state_file: nil} )

			expect( ZMQ::Timer ).to_not receive( :new )

			expect( manager.start_state_checkpointing ).to be_nil
		end


		it "writes a checkpoint if it receives a SIGUSR1"


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


	describe "tree traversal" do

		let( :tree ) do
			#                        router
			# host_a                 host_b              host_c
			# www smtp imap          www nfs ssh         www

			[
				testing_node( 'router' ),
					testing_node( 'host_a', 'router' ),
						testing_node( 'host_a_www', 'host_a' ),
						testing_node( 'host_a_smtp', 'host_a' ),
						testing_node( 'host_a_imap', 'host_a' ),
					testing_node( 'host_b', 'router' ),
						testing_node( 'host_b_www', 'host_b' ),
						testing_node( 'host_b_nfs', 'host_b' ),
						testing_node( 'host_b_ssh', 'host_b' ),
					testing_node( 'host_c', 'router' ),
						testing_node( 'host_c_www', 'host_c' ),
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
			manager.nodes.each {|_, node| node.status = :up }
			manager.nodes[ 'host_a' ].update( error: "ping failed" )
			expect( manager.nodes[ 'host_a' ] ).to be_down
			manager.nodes[ 'host_c' ].update( error: "gamma rays" )
			expect( manager.nodes[ 'host_c' ] ).to be_down
			manager.nodes[ 'host_b_nfs' ].
				update( ack: {sender: 'nancy_kerrigan', message: 'bad case of disk rot'} )
			expect( manager.nodes[ 'host_b_nfs' ] ).to be_disabled
			expect( manager.nodes[ 'host_b_nfs' ] ).to_not be_down

			iter = manager.reachable_nodes

			expect( iter ).to be_a( Enumerator )

			nodes = iter.map( &:identifier )
			expect( nodes ).to include(
				"_",
				"router",
				"host_b",
				"host_b_www",
				"host_b_ssh"
			)
			expect( nodes ).to_not include(
				"host_b_nfs",
				"host_c",
				"host_c_www",
				"host_a",
				'host_a_www',
				'host_a_smtp',
				'host_a_imap'
			)
		end


		it "can create an Enumerator for all of a node's parents from leaf to root"

	end


	describe "node updates and events" do

		let( :tree ) do
			#                        router
			# host_a                 host_b              host_c
			# www smtp imap          www nfs ssh         www

			[
				testing_node( 'router' ),
					testing_node( 'host_a', 'router' ),
						testing_node( 'host_a_www', 'host_a' ),
						testing_node( 'host_a_smtp', 'host_a' ),
						testing_node( 'host_a_imap', 'host_a' ),
					testing_node( 'host_b', 'router' ),
						testing_node( 'host_b_www', 'host_b' ),
						testing_node( 'host_b_nfs', 'host_b' ),
						testing_node( 'host_b_ssh', 'host_b' ),
					testing_node( 'host_c', 'router' ),
						testing_node( 'host_c_www', 'host_c' ),
			]
		end

		let( :manager ) do
			instance = described_class.new
			instance.load_tree( tree )
			instance
		end


		it "can fetch a Hash of node states" do
			states = manager.fetch_matching_node_states( {}, [] )
			expect( states.size ).to eq( manager.nodes.size )
			expect( states ).to include( 'host_b_nfs', 'host_c', 'router' )
			expect( states['host_b_nfs'] ).to be_a( Hash )
			expect( states['host_c'] ).to be_a( Hash )
			expect( states['router'] ).to be_a( Hash )
		end


		it "can update an event by identifier" do
			manager.update_node( 'host_b_www', http: { status: 200 } )
			expect(
				manager.nodes['host_b_www'].properties
			).to include( 'http' => { 'status' => 200 } )
		end


		it "ignores updates to an identifier that is not (any longer) in the tree" do
			expect {
				manager.update_node( 'host_y', asset_tag: '2by-n86y7t' )
			}.to_not raise_error
		end


		it "propagates events from an update up the node tree" do
			expect( manager.root ).to receive( :publish_events ).
				at_least( :once ).
				and_call_original
			expect( manager.nodes['host_c'] ).to receive( :publish_events ).
				at_least( :once ).
				and_call_original
			manager.update_node( 'host_c_www', response_status: 504, error: 'Timeout talking to web service.' )
		end


		it "only propagates events to a node's ancestors" do
			expect( manager.root ).to receive( :publish_events ).
				at_least( :once ).
				and_call_original
			expect( manager.nodes['host_c'] ).to_not receive( :publish_events )

			manager.update_node( 'host_b_www', response_status: 504, error: 'Timeout talking to web service.' )
		end

	end


	describe "subscriptions" do

		let( :tree ) {[ testing_node('host_c') ]}
		let( :manager ) do
			instance = described_class.new
			instance.load_tree( tree )
			instance
		end


		it "can attach subscriptions to a node by its identifier" do
			sub = subid = nil
			expect {
				sub = manager.create_subscription( 'host_c', 'node.update', type: 'host' )
			}.to change { manager.subscriptions.size }.by( 1 )

			node = manager.subscriptions[ sub.id ]

			expect( sub ).to be_a( Arborist::Subscription )
			expect( node ).to be( manager.nodes['host_c'] )
		end


		it "can detach subscriptions from a node given the subscription ID" do
			sub = manager.create_subscription( 'host_c', 'node.ack', type: 'service' )
			rval = nil

			expect {
				rval = manager.remove_subscription( sub.id )
			}.to change { manager.subscriptions.size }.by( -1 ).and(
				change { manager.nodes['host_c'].subscriptions.size }.by( -1 )
			)

			expect( rval ).to be( sub )
		end

	end


	describe "sockets" do

		let( :zmq_context ) { Arborist.zmq_context }
		let( :zmq_loop ) { instance_double(ZMQ::Loop) }
		let( :tree_sock ) { instance_double(ZMQ::Socket::Rep, "tree API socket") }
		let( :event_sock ) { instance_double(ZMQ::Socket::Pub, "event socket") }
		let( :tree_pollitem ) { instance_double(ZMQ::Pollitem, "tree API pollitem") }
		let( :event_pollitem ) { instance_double(ZMQ::Pollitem, "event API pollitem") }
		let( :signal_timer ) { instance_double(ZMQ::Timer, "signal timer") }

		before( :each ) do
			allow( ZMQ::Loop ).to receive( :new ).and_return( zmq_loop )

			allow( zmq_context ).to receive( :socket ).with( :REP ).and_return( tree_sock )
			allow( zmq_context ).to receive( :socket ).with( :PUB ).and_return( event_sock )

			allow( zmq_loop ).to receive( :remove ).with( tree_pollitem )
			allow( zmq_loop ).to receive( :remove ).with( event_pollitem )

			allow( tree_pollitem ).to receive( :pollable ).and_return( tree_sock )
			allow( tree_sock ).to receive( :close )
			allow( event_pollitem ).to receive( :pollable ).and_return( event_sock )
			allow( event_sock ).to receive( :close )
		end


		it "sets up its sockets with handlers and starts the ZMQ loop when started" do
			expect( tree_sock ).to receive( :bind ).with( Arborist.tree_api_url )
			expect( tree_sock ).to receive( :linger= ).with( 0 )

			expect( event_sock ).to receive( :bind ).with( Arborist.event_api_url )
			expect( event_sock ).to receive( :linger= ).with( 0 )

			expect( ZMQ::Pollitem ).to receive( :new ).with( tree_sock, ZMQ::POLLIN|ZMQ::POLLOUT ).
				and_return( tree_pollitem )
			expect( ZMQ::Pollitem ).to receive( :new ).with( event_sock, ZMQ::POLLOUT ).
				and_return( event_pollitem )

			expect( tree_pollitem ).to receive( :handler= ).
				with( an_instance_of(Arborist::Manager::TreeAPI) )
			expect( zmq_loop ).to receive( :register ).with( tree_pollitem )
			expect( event_pollitem ).to receive( :handler= ).
				with( an_instance_of(Arborist::Manager::EventPublisher) )
			expect( zmq_loop ).to receive( :register ).with( event_pollitem )

			expect( ZMQ::Timer ).to receive( :new ).
				with( described_class::SIGNAL_INTERVAL, 0, manager.method(:process_signal_queue) ).
				and_return( signal_timer )
			expect( zmq_loop ).to receive( :register_timer ).with( signal_timer )
			expect( zmq_loop ).to receive( :start )

			expect( zmq_loop ).to receive( :remove ).with( tree_pollitem )
			expect( zmq_loop ).to receive( :remove ).with( event_pollitem )

			manager.run
		end
	end


end

