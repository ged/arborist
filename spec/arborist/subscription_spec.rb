#!/usr/bin/env rspec -cfd

require_relative '../spec_helper'

require 'arborist/subscription'
require 'arborist/node/host'
require 'arborist/node/service'


describe Arborist::Subscription do

	let( :host_node ) do
		Arborist::Node.create( 'host', 'testnode' ) do
			description "Test host"
			address '192.168.1.1'
		end
	end
	let( :service_node ) do
		host_node.service( 'ssh' )
	end
	let( :published_events ) {[]}
	let( :subscription ) do
		described_class.new( 'node.delta', type: 'host', &published_events.method(:push) )
	end


	it "raises an error if created without a callback block" do
		expect {
			described_class.new
		}.to raise_error( LocalJumpError, /requires a callback block/i )
	end


	it "generates a unique ID when it's created" do
		expect( subscription.id ).to match( /^\S{16,}$/ )
	end


	it "publishes events which are of the desired type and have matching criteria" do
		event = Arborist::Event.create( 'node_delta', host_node, status: ['up', 'down'] )

		subscription.on_events( event )

		expect( published_events ).to eq([ subscription.id, event ])
	end


	it "publishes events which are of any type if the specified type is `nil`" do
		subscription = described_class.new( &published_events.method(:push) )
		event1 = Arborist::Event.create( 'node_delta', host_node, status: ['up', 'down'] )
		event2 = Arborist::Event.create( 'node_update', host_node )

		subscription.on_events( event1, event2 )

		expect( published_events ).to eq([
			subscription.id, event1,
			subscription.id, event2
		])
	end


	it "doesn't publish events which are of the desired type but don't have matching criteria" do
		event = Arborist::Event.create( 'node_delta', service_node, status: ['up', 'down'] )

		subscription.on_events( event )

		expect( published_events ).to be_empty
	end


	it "doesn't publish events which have matching criteria but aren't of the desired type" do
		event = Arborist::Event.create( 'node_update', host_node )

		subscription.on_events( event )

		expect( published_events ).to be_empty
	end

end

