#!/usr/bin/env rspec -cfd

require_relative '../../spec_helper'

require 'arborist/event/node_update'


describe Arborist::Event::NodeUpdate do

	class TestNode < Arborist::Node; end


	let( :node ) do
		TestNode.new( 'foo' ) do
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


	describe "subscription support" do

		it "matches a subscription with only an event type if the type is the same" do
			sub = Arborist::Subscription.new( :publisher, 'node.update' )
			event = described_class.new( node )

			expect( event ).to match( sub )
		end


		it "matches a subscription with a matching event type and matching criteria" do
			sub = Arborist::Subscription.new( :publisher, 'node.update', 'tag' => 'chunker' )
			event = described_class.new( node )

			expect( event ).to match( sub )
		end


		it "doesn't match a subscription with a matching event type if the criteria don't match" do
			sub = Arborist::Subscription.new( :publisher, 'node.update', 'tag' => 'looper' )
			event = described_class.new( node )

			expect( event ).to_not match( sub )
		end


	end


end

