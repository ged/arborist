#!/usr/bin/env rspec -cfd

require_relative '../spec_helper'

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


		it "can have a node added to it" do
			manager.add_node( node )
			expect( manager.nodes ).to include( 'italian_lessons' )
			expect( manager.nodes['italian_lessons'] ).to be( node )
		end


		it "can load its tree from an Enumerator that yields nodes" do
			manager.load_tree([ node, node2, node3 ])
			expect( manager.nodes ).to include( 'italian_lessons', 'french_laundry', 'german_oak_cats' )
			expect( manager.nodes['italian_lessons'] ).to be( node )
			expect( manager.nodes['french_laundry'] ).to be( node2 )
			expect( manager.nodes['german_oak_cats'] ).to be( node3 )
		end


		it "can replace an existing node" do
			manager.add_node( node )
			another_node = node_class.new( 'italian_lessons' )
			manager.add_node( another_node )

			expect( manager.nodes ).to include( 'italian_lessons' )
			expect( manager.nodes['italian_lessons'] ).to_not be( node )
			expect( manager.nodes['italian_lessons'] ).to be( another_node )
		end


		it "can have a node removed from it" do
			manager.add_node( node )
			deleted_node = manager.remove_node( 'italian_lessons' )

			expect( deleted_node ).to be( node )
			expect( manager.nodes ).to_not include( 'italian_lessons' )
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


		it "can create an Enumerator for all of a node's parents from leaf to root"

	end

end

