#!/usr/bin/env rspec -cfd

require_relative '../spec_helper'

require 'arborist/event'


describe Arborist::Event do

	it "derives its type name from its class" do
		payload = { 'status' => ['up', 'down'] }
		expect( TestEvent.new(payload).type ).to eq( 'test.event' )
	end


	it "copies the payload it's constructed with" do
		payload = { 'status' => ['up', 'down'] }

		ev = TestEvent.create( TestEvent, payload )
		payload.clear

		expect( ev.payload ).to include( 'status' )
	end


	describe "subscription support" do

		it "matches a subscription with only an event type if the type is the same" do
			sub = Arborist::Subscription.new( 'test.event' ) {}
			event = described_class.create( TestEvent, [] )

			expect( event ).to match( sub )
		end


		it "always matches a subscription with a nil event type" do
			sub = Arborist::Subscription.new {}
			event = described_class.create( TestEvent, [] )

			expect( event ).to match( sub )
		end

	end


	describe "serialization support" do

		it "can represent itself as a Hash" do
			payload = { 'status' => ['up', 'down'] }
			ev = TestEvent.create( TestEvent, payload )

			result = ev.to_h

			expect( result ).to include( 'type', 'data' )

			expect( result['type'] ).to eq( 'test.event' )
			expect( result['data'] ).to eq( payload )
		end


	end

end

