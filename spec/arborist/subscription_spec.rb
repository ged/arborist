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


	let( :subscription ) do
		described_class.new( 'node.delta', type: 'host' )
	end


	it "generates a unique ID when it's created" do
		expect( subscription.id ).to match( /^\S{16,}$/ )
	end


	it "matches events which are of the desired type and have matching criteria" do
		event = Arborist::Event.create( 'node_delta', host_node, status: ['up', 'down'] )
		expect( event ).to match( subscription )
	end


	it "matches events which are of any type if the specified type is `nil`" do
		subscription = described_class.new
		event1 = Arborist::Event.create( 'node_delta', host_node, status: ['up', 'down'] )
		event2 = Arborist::Event.create( 'sys_reloaded' )
		expect([ event1, event2 ]).to all( match(subscription) )
	end


	it "doesn't match events which are of the desired type but don't have matching criteria" do
		event = Arborist::Event.create( 'node_delta', service_node, status: ['up', 'down'] )
		expect( event ).to_not match( subscription )
	end

	it "doesn't match events which have matching criteria but aren't of the desired type" do
		event = Arborist::Event.create( 'node_update', host_node )
		expect( event ).to_not match( subscription )
	end


end

