#!/usr/bin/env rspec -cfd

require_relative '../spec_helper'

require 'arborist/subscription'


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
	let( :publisher ) do
		instance_double( Arborist::Manager::EventPublisher )
	end
	let( :subscription ) do
		described_class.new( publisher, 'node.delta', type: 'host' )
	end


	it "generates a unique ID when it's created" do
		expect( subscription.id ).to match( /^\S{16,}$/ )
	end


	it "publishes events which are of the desired type and have matching criteria" do
		event = Arborist::Event.create( 'node_delta', host_node, status: ['up', 'down'] )

		expect( publisher ).to receive( :publish ).with( subscription.id, event )

		subscription.on_events( event )
	end


	it "publishes events which are of any type if the specified type is `nil`" do
		subscription = described_class.new( publisher )
		event1 = Arborist::Event.create( 'node_delta', host_node, status: ['up', 'down'] )
		event2 = Arborist::Event.create( 'sys_reloaded' )

		expect( publisher ).to receive( :publish ).with( subscription.id, event1 )
		expect( publisher ).to receive( :publish ).with( subscription.id, event2 )

		subscription.on_events( event1, event2 )
	end


	it "doesn't publish events which are of the desired type but don't have matching criteria" do
		event = Arborist::Event.create( 'node_delta', service_node, status: ['up', 'down'] )

		expect( publisher ).to_not receive( :publish )

		subscription.on_events( event )
	end


	it "doesn't publish events which have matching criteria but aren't of the desired type" do
		event = Arborist::Event.create( 'node_update', host_node )

		expect( publisher ).to_not receive( :publish )

		subscription.on_events( event )
	end

end

