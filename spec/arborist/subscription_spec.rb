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


	it "raises an error if created without a callback block" do
		expect {
			described_class.new
		}.to raise_error( LocalJumpError, /requires a callback block/i )
	end


	it "generates a unique ID when it's created" do
		subscription = described_class.new( 'node.delta', type: 'host' ) do |*|
			# no-op
		end
		expect( subscription.id ).to match( /^\S{16,}$/ )
	end


	it "publishes events which are of the desired type and have matching criteria" do
		published_events = []
		subscription = described_class.new( 'node.delta', type: 'host' ) do |_, event|
			published_events << event
		end
		event = Arborist::Event.create( 'node_delta', host_node, 'status' => ['up', 'down'] )

		subscription.on_events( event )

		expect( published_events ).to eq([ event ])
	end


	it "publishes events which are of any type if the specified type is `nil`" do
		published_events = []
		subscription = described_class.new( nil, type: 'host' ) do |_, event|
			published_events << event
		end

		event1 = Arborist::Event.create( 'node_delta', host_node, status: ['up', 'down'] )
		event2 = Arborist::Event.create( 'node_update', host_node )

		subscription.on_events( event1, event2 )

		expect( published_events ).to eq([ event1, event2 ])
	end


	it "doesn't publish events which are of the desired type but don't have matching criteria" do
		published_events = []
		subscription = described_class.new( 'node.delta', type: 'host' ) do |_, event|
			published_events << event
		end

		event = Arborist::Event.create( 'node_delta', service_node, status: ['up', 'down'] )

		subscription.on_events( event )

		expect( published_events ).to be_empty
	end


	it "doesn't publish events which have matching criteria but aren't of the desired type" do
		published_events = []
		subscription = described_class.new( 'node.delta', type: 'host' ) do |_, event|
			published_events << event
		end

		event = Arborist::Event.create( 'node_update', host_node )

		subscription.on_events( event )

		expect( published_events ).to be_empty
	end


	it "doesn't publish events which have matching negative criteria" do
		published_events = []
		subscription = described_class.new( 'node.update', type: 'host' ) do |_, event|
			Loggability[ Arborist ].warn "Published event: %p" % [ event ]
			published_events << event
		end
		subscription.exclude( 'status' => 'down' )

		events = host_node.update( error: "Angry bees." )
		subscription.on_events( events )

		events = host_node.update( error: nil )
		subscription.on_events( events )

		expect( published_events ).to all( be_a Arborist::Event::NodeUpdate )
		expect( published_events.length ).to eq( 1 )
	end


	it "doesn't publish delta events which have matching negative criteria" do
		published_events = []
		subscription = described_class.new( 'node.delta', type: 'host' ) do |_, event|
			published_events << event
		end
		subscription.exclude( 'delta' => {'status' => ['unknown', 'down']} )

		events = host_node.update( error: "Angry badgers." )
		subscription.on_events( events )

		events = host_node.update( error: nil )
		subscription.on_events( events )

		expect( published_events.length ).to eq( 1 )
		expect( published_events.first ).to be_a( Arborist::Event::NodeDelta )
		expect( published_events.first.payload['status'] ).to eq( ['down', 'up'] )
	end

end

