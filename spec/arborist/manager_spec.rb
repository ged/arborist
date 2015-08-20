#!/usr/bin/env rspec -cfd

require_relative '../spec_helper'

require 'timecop'
require 'arborist/manager'


describe Arborist::Manager do

	after( :each ) do
		Arborist::Node::Root.reset
	end


	let( :manager ) { described_class.new }

	let( :node_class ) do
		Class.new( Arborist::Node )
	end


	#
	# Fixture Functions
	#

	def testing_node( identifier, parent=nil )
		node = node_class.new( identifier )
		node.parent( parent ) if parent
		return node
	end


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


	context "a new empty manager" do

		let( :node ) do
			node_class.new 'italian_lessons'
		end
		let( :node2 ) do
			node_class.new 'french_laundry'
		end
		let( :node3 ) do
			node_class.new 'german_oak_cats'
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
			another_node = node_class.new( 'italian_lessons' )
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
			orphan = node_class.new( 'orphan' ) do
				parent 'daddy_warbucks'
			end

			expect {
				manager.load_tree([ orphan ])
			}.to raise_error( /no parent 'daddy_warbucks' node loaded for/i )
		end


		it "grafts a node into the tree when one with a previously unknown identifier is added" do
			new_node = node_class.new( 'new' ) do
				parent 'branch'
			end

			manager.add_node( new_node )
			expect( manager.nodes['branch'].children ).to include( 'new' )
		end


		it "replaces a node in the tree when a node with an existing identifier is added" do
			updated_node = node_class.new( 'leaf' ) do
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

			iter = manager.reachable_nodes

			expect( iter ).to be_a( Enumerator )

			nodes = iter.to_a
			expect( nodes.size ).to eq( 6 )
			expect( nodes.map(&:identifier) ).to include(
				"_",
				"router",
				"host_b",
				"host_b_www",
				"host_b_nfs",
				"host_b_ssh"
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
			expect( manager.root ).to receive( :find_matching_subscriptions ).
				at_least(:once).
				and_call_original
			expect( manager.nodes['host_c'] ).to receive( :find_matching_subscriptions ).
				at_least(:once).
				and_call_original
			manager.update_node( 'host_c_www', response_status: 504, error: 'Timeout talking to web service.' )
		end


		it "only propagates events to a node's ancestors" do
			expect( manager.root ).to receive( :find_matching_subscriptions ).
				at_least(:once).
				and_call_original
			expect( manager.nodes['host_c'] ).to_not receive( :find_matching_subscriptions )

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
				subid = manager.create_subscription( 'host_c', 'node.update', type: 'host' )
			}.to change { manager.subscriptions.size }.by( 1 )

			sub = manager.subscriptions[ subid ]

			expect( sub ).to be_a( Arborist::Subscription )
			expect( manager.nodes['host_c'].subscriptions ).to include( sub )
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

			expect( ZMQ::Pollitem ).to receive( :new ).with( tree_sock, ZMQ::POLLIN ).
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

