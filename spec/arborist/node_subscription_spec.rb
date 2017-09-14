#!/usr/bin/env rspec -cfd

require_relative '../spec_helper'

require 'arborist/node_subscription'


describe Arborist::NodeSubscription do


	it "can be created with just a node" do
		node = Arborist::Node.create( 'host', 'testy' )
		expect( described_class.new(node) ).to be_a( described_class )
	end


	it "raises an error if called with no node" do
		expect {
			described_class.new
		}.to raise_error( ArgumentError )
	end


	it "raises an error if called with something that doesn't handle events" do
		expect {
			described_class.new( "hi i'm a little teapot" )
		}.to raise_error( NameError, /handle_event/ )
	end


	it "uses its node's identifier for its ID" do
		node = Arborist::Node.create( 'host', 'testy' )
		sub = described_class.new( node )

		expect( sub.id ).to eq( 'testy-subscription' )
	end


	it "matches all events" do
		node = Arborist::Node.create( 'host', 'testy' )
		sub = described_class.new( node )
		events = [
			Arborist::Event.create( 'node_update', node ),
			Arborist::Event.create( 'node_delta', node, status: ['up', 'down'] ),
			Arborist::Event.create( 'node_update', node ),
			Arborist::Event.create( 'node_quieted', node ),
			Arborist::Event.create( 'node_acked', node )
		]

		expect( events ).to all( match sub )
	end

end

