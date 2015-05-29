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


	describe "sockets" do

		let( :zmq_context ) { instance_double(ZMQ::Context) }
		let( :tree_sock ) { instance_double(ZMQ::Socket::Rep, "tree API socket") }
		let( :observer_sock ) { instance_double(ZMQ::Socket::Pull, "observer API socket") }
		let( :event_sock ) { instance_double(ZMQ::Socket::Pub, "event socket") }


		before( :each ) do
			Arborist.instance_variable_set( :@zmq_context, zmq_context )

			allow( zmq_context ).to receive( :socket ).with( :REP ).and_return( tree_sock )
			allow( zmq_context ).to receive( :socket ).with( :PULL ).and_return( observer_sock )
			allow( zmq_context ).to receive( :socket ).with( :PUB ).and_return( event_sock )

			allow( ZMQ::Loop ).to receive( :run ).and_yield()
		end

		after( :each ) do
			Arborist.instance_variable_set( :@zmq_ctx, nil )
		end



		it "sets up its sockets with handlers and starts the ZMQ loop when started" do
			expect( tree_sock ).to receive( :bind ).with( described_class.tree_api_url )
			expect( tree_sock ).to receive( :linger= ).with( 0 )

			expect( event_sock ).to receive( :bind ).with( described_class.event_api_url )
			expect( event_sock ).to receive( :linger= ).with( 0 )

			expect( ZMQ::Loop ).to receive( :run ).and_yield()

			expect( ZMQ::Loop ).to receive( :register_readable ).
				with( tree_sock, Arborist::Manager::TreeAPI, manager )
			expect( ZMQ::Loop ).to receive( :register_writable ).
				with( event_sock, Arborist::Manager::EventPublisher, manager )

			expect( ZMQ::Loop ).to receive( :add_periodic_timer ).
				with( described_class::SIGNAL_INTERVAL )

			expect( ZMQ::Loop ).to receive( :instance ).and_return( true )
			expect( ZMQ::Loop ).to receive( :remove ).with( tree_sock )
			expect( ZMQ::Loop ).to receive( :remove ).with( event_sock )

			manager.run
		end
	end
end

