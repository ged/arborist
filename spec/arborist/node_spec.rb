#!/usr/bin/env rspec -cfd

require_relative '../spec_helper'

require 'time'
require 'arborist/node'


class TestNode < Arborist::Node; end


describe Arborist::Node do

	let( :concrete_class ) { TestNode }

	let( :identifier ) { 'the_identifier' }
	let( :identifier2 ) { 'the_other_identifier' }

	it "can be loaded from a file" do
		concrete_instance = nil
		expect( Kernel ).to receive( :load ).with( "a/path/to/a/node.rb" ) do
			concrete_instance = concrete_class.new( identifier )
		end

		result = described_class.load( "a/path/to/a/node.rb" )
		expect( result ).to be_an( Array )
		expect( result.length ).to eq( 1 )
		expect( result ).to include( concrete_instance )
	end


	it "can load multiple nodes from a single file" do
		concrete_instance1 = concrete_instance2 = nil
		expect( Kernel ).to receive( :load ).with( "a/path/to/a/node.rb" ) do
			concrete_instance1 = concrete_class.new( identifier )
			concrete_instance2 = concrete_class.new( identifier2 )
		end

		result = described_class.load( "a/path/to/a/node.rb" )
		expect( result ).to be_an( Array )
		expect( result.length ).to eq( 2 )
		expect( result ).to include( concrete_instance1, concrete_instance2 )
	end


	it "knows what its identifier is" do
		expect( described_class.new('good_identifier').identifier ).to eq( 'good_identifier' )
	end


	it "accepts identifiers with hyphens" do
		expect( described_class.new('router_nat-pmp').identifier ).to eq( 'router_nat-pmp' )
	end


	it "raises an error if the node identifier is invalid" do
		expect {
		   described_class.new 'bad identifier'
		}.to raise_error( RuntimeError, /identifier/i )
	end


	context "an instance of a concrete subclass" do

		let( :node ) { concrete_class.new(identifier) }
		let( :child_node ) do
			concrete_class.new(identifier2) do
				parent 'the_identifier'
			end
		end


		it "can declare what its parent is by identifier" do
			expect( child_node.parent ).to eq( identifier )
		end


		it "can have child nodes added to it" do
			node.add_child( child_node )
			expect( node.children ).to include( child_node.identifier )
		end


		it "can have child nodes appended to it" do
			node << child_node
			expect( node.children ).to include( child_node.identifier )
		end


		it "raises an error if a node which specifies a different parent is added to it" do
			not_child_node = concrete_class.new(identifier2) do
				parent 'youre_not_my_mother'
			end
			expect {
				node.add_child( not_child_node )
			}.to raise_error( /not a child of/i )
		end


		it "doesn't add the same child more than once" do
			node.add_child( child_node )
			node.add_child( child_node )
			expect( node.children.size ).to eq( 1 )
		end


		it "knows it doesn't have any children if it's empty" do
			expect( node ).to_not have_children
		end


		it "knows it has children if subnodes have been added" do
			node.add_child( child_node )
			expect( node ).to have_children
		end


		it "knows how to remove one of its children" do
			node.add_child( child_node )
			node.remove_child( child_node )
			expect( node ).to_not have_children
		end


		describe "status" do

			it "starts out in `unknown` status" do
				expect( node ).to be_unknown
			end


			it "transitions to `up` status if its state is updated with no `error` property" do
				node.update( tested: true )
				expect( node ).to be_up
			end


			it "transitions to `down` status if its state is updated with an `error` property" do
				node.update( error: "Couldn't talk to it!" )
				expect( node ).to be_down
			end

			it "transitions from `down` to `acked` status if it's updated with an `ack` property" do
				node.status = 'down'
				node.error = 'Something is wrong | he falls | betraying the trust | "\
					"there is a disaster in his life.'
				node.update( ack: {message: "Leitmotiv", sender: 'ged'}  )
				expect( node ).to be_acked
			end

			it "transitions to `up` from `acked` status if it's updated with an `ack` property" do
				node.update( ack: {message: "Maintenance", sender: 'mahlon'}, error: "Offlined"  )
				node.update( ping_time: 0.02 )

				expect( node ).to be_up
			end

		end


		describe "Properties API" do

			it "is initialized with an empty set" do
				expect( node.properties ).to be_empty
			end

			it "can attach arbitrary values to the node" do
				node.update( 'cider' => 'tasty' )
				expect( node.properties['cider'] ).to eq( 'tasty' )
			end

			it "replaces existing values on update" do
				node.properties.replace({
					'cider' => 'tasty',
					'cider_size' => '16oz',
				})
				node.update( 'cider_size' => '8oz' )

				expect( node.properties ).to include(
					'cider' => 'tasty',
					'cider_size' => '8oz'
				)
			end

			it "replaces nested values on update" do
				node.properties.replace({
					'cider' => {
						'description' => 'tasty',
						'size' => '16oz',
					},
					'sausage' => {
						'description' => 'pork',
						'size' => 'huge',
					},
					'music' => '80s'
				})
				node.update(
					'cider' => {'size' => '8oz'},
					'sausage' => 'Linguiça',
					'music' => {
						'genre' => '80s',
						'artist' => 'The Smiths'
					}
				)

				expect( node.properties ).to eq(
					'cider' => {
						'description' => 'tasty',
						'size' => '8oz',
					},
					'sausage' => 'Linguiça',
					'music' => {
						'genre' => '80s',
						'artist' => 'The Smiths'
					}
				)
			end

			it "removes pairs whose value is nil" do
				node.properties.replace({
					'cider' => {
						'description' => 'tasty',
						'size' => '16oz',
					},
					'sausage' => {
						'description' => 'pork',
						'size' => 'huge',
					},
					'music' => '80s'
				})
				node.update(
					'cider' => {'size' => nil},
					'sausage' => nil,
					'music' => {
						'genre' => '80s',
						'artist' => 'The Smiths'
					}
				)

				expect( node.properties ).to eq(
					'cider' => {
						'description' => 'tasty',
					},
					'music' => {
						'genre' => '80s',
						'artist' => 'The Smiths'
					}
				)
			end
		end


		describe "Enumeration" do

			it "iterates over its children for #each" do
				parent = node
				parent <<
					concrete_class.new('child1') { parent 'the_identifier' } <<
					concrete_class.new('child2') { parent 'the_identifier' } <<
					concrete_class.new('child3') { parent 'the_identifier' }

				expect( parent.map(&:identifier) ).to eq([ 'child1', 'child2', 'child3' ])
			end

		end


		describe "Serialization" do

			let( :node ) do
				concrete_class.new( 'foo' ) do
					parent 'bar'
					description "The prototypical node"
					tags :chunker, :hunky, :flippin, :hippo

					update( 'song' => 'Around the World', 'artist' => 'Daft Punk', 'length' => '7:09' )
				end
			end


			it "can return a Hash of serializable node data" do
				result = node.to_hash

				expect( result ).to be_a( Hash )
				expect( result ).to include(
					:identifier,
					:parent, :description, :tags, :properties, :status, :ack,
					:last_contacted, :status_changed, :error
				)
				expect( result[:identifier] ).to eq( 'foo' )
				expect( result[:type] ).to eq( 'testnode' )
				expect( result[:parent] ).to eq( 'bar' )
				expect( result[:description] ).to eq( node.description )
				expect( result[:tags] ).to eq( node.tags )
				expect( result[:properties] ).to eq( node.properties )
				expect( result[:status] ).to eq( node.status )
				expect( result[:ack] ).to be_nil
				expect( result[:last_contacted] ).to eq( node.last_contacted.iso8601 )
				expect( result[:status_changed] ).to eq( node.status_changed.iso8601 )
				expect( result[:error] ).to be_nil
			end


			it "can be reconstituted from a serialized Hash of node data" do
				hash = node.to_hash
				cloned_node = concrete_class.from_hash( hash )

				expect( cloned_node ).to eq( node )
			end


			it "an ACKed node stays ACKed when reconstituted" do
				node.update(ack: {
					message: 'We know about the fire.  It rages on.',
					sender: '1986 Labyrinth David Bowie'
				})
				cloned_node = concrete_class.from_hash( node.to_hash )

				expect( cloned_node ).to be_acked
			end


			it "can be marshalled" do
				data = Marshal.dump( node )
				cloned_node = Marshal.load( data )

				expect( cloned_node ).to eq( node )
			end


		end

	end


	describe "event system" do

		let( :node ) do
			concrete_class.new( 'foo' ) do
				parent 'bar'
				description "The prototypical node"
				tags :chunker, :hunky, :flippin, :hippo

				update(
					'song' => 'Around the World',
					'artist' => 'Daft Punk',
					'length' => '7:09',
					'cider' => {
						'description' => 'tasty',
						'size' => '16oz',
					},
					'sausage' => {
						'description' => 'pork',
						'size' => 'monsterous',
						'price' => {
							'units' => 1200,
							'currency' => 'usd'
						}
					},
					'music' => '80s'
				)
			end
		end


		it "generates a node.update event on update" do
			events = node.update( 'song' => "Around the World" )

			expect( events ).to be_an( Array )
			expect( events ).to all( be_a(Arborist::Event) )
			expect( events.size ).to eq( 1 )
			expect( events.first.type ).to eq( 'node.update' )
			expect( events.first.data ).to eq( node.fetch_values )
		end


		it "generates a node.delta event when an update changes a value" do
			events = node.update(
				'song' => "Motherboard",
				'sausage' => {
					'price' => {
						'currency' => 'eur'
					}
				}
			)

			expect( events ).to be_an( Array )
			expect( events ).to all( be_a(Arborist::Event) )
			expect( events.size ).to eq( 2 )

			delta_event = events.find {|ev| ev.type == 'node.delta' }

			expect( delta_event.data ).to eq({
				'song' => ['Around the World' , 'Motherboard'],
				'sausage' => {
					'price' => {
						'currency' => ['usd', 'eur']
					}
				}
			})
		end


		it "includes status changes in delta events" do
			events = node.update( error: "Couldn't talk to it!" )
			delta_event = events.find {|ev| ev.type == 'node.delta' }

			expect( delta_event.data ).to include( 'status' => ['up', 'down'] )
		end


		it "generates a node.acked event when a node is acked" do
			events = node.update(ack: {
				message: "I have a poisonous friend. She's living in the house.",
				sender: 'Seabound'
			})

			expect( events.size ).to eq( 3 )
			ack_event = events.find {|ev| ev.type == 'node.acked' }

			expect( ack_event ).to be_a( Arborist::Event )
			expect( ack_event.data ).to include( sender: 'Seabound' )
		end

	end


	describe "subscriptions" do


		it "allows the addition of a Subscription"


		it "allows the removal of a Subscription"


		it "publishes events which match one of its subscriptions to the associated subscriber ID"

	end

end

