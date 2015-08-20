#!/usr/bin/env rspec -cfd

require_relative '../../spec_helper'

require 'arborist/manager/event_publisher'


describe Arborist::Manager::EventPublisher do

	let( :socket ) { instance_double( ZMQ::Socket::Pub ) }
	let( :pollitem ) { instance_double( ZMQ::Pollitem, pollable: socket ) }
	let( :zloop ) { instance_double( ZMQ::Loop ) }

	let( :manager ) { Arborist::Manager.new }
	let( :event ) { Arborist::Event.create(TestEvent, 'stuff') }

	let( :publisher ) { described_class.new(pollitem, manager, zloop) }


	it "starts out registered for writing" do
		expect( publisher ).to be_registered
	end


	it "unregisters itself if told to write with an empty event queue" do
		expect( zloop ).to receive( :remove ).with( socket )
		expect {
			publisher.on_writable
		}.to change { publisher.registered? }.to( false )
	end


	it "registers itself if it's not already when an event is appended" do
		# Cause the socket to become unregistered
		allow( zloop ).to receive( :remove )
		publisher.on_writable

		expect( zloop ).to receive( :register ).with( socket )

		expect {
			publisher.publish( 'identifier-00aa', event )
		}.to change { publisher.registered? }.to( true )
	end


	it "publishes events with their identifier" do
		identifier = '65b2430b-6855-4961-ab46-d742cf4456a1'

		expect( socket ).to receive( :sendm ).with( identifier )
		expect( socket ).to receive( :send ) do |raw_data|
			ev = MessagePack.unpack( raw_data )
			expect( ev ).to include( 'type', 'data' )

			expect( ev['type'] ).to eq( 'test.event' )
			expect( ev['data'] ).to eq( 'stuff' )
		end
		expect( zloop ).to receive( :remove ).with( socket )

		publisher.publish( identifier, event )
		publisher.on_writable
	end


end


