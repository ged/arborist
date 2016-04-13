#!/usr/bin/env rspec -cfd

require_relative '../../spec_helper'
require 'arborist/node/ack'


describe Arborist::Node::Ack do

	it "can be constructed with a sender and a message" do
		result = described_class.new( "a message", "a sender" )
		expect( result ).to be_a( described_class )
		expect( result.message ).to eq( "a message" )
		expect( result.sender ).to eq( "a sender" )

		expect( result.time ).to be_within( 2 ).of( Time.now )
		expect( result.via ).to be_nil
	end


	it "requires a sender" do
		expect {
			described_class.from_hash( message: 'hi!' )
		}.to raise_error( ArgumentError, /missing required ack sender/i )
	end

	it "requires a message" do
		expect {
			described_class.from_hash( sender: 'slick rick' )
		}.to raise_error( ArgumentError, /missing required ack message/i )
	end

	it "can be round-tripped to a Hash and back" do
		result = described_class.new( 'boom', 'explosivo' )
		expect( described_class.from_hash(result.to_h) ).to eq( result )
	end


	it "can describe itself" do
		ack = described_class.new( "someone else's problem", "Hike Mix" )
		expect( ack.description ).to match( /by hike mix -- someone else's problem/i )
	end

	it "can describe itself with a via source" do
		ack = described_class.new( "someone else's problem", "Hike Mix", via: "sms" )
		expect( ack.description ).to match( /by hike mix via sms -- someone else's problem/i )
	end


	describe "time argument" do

		it "can be constructed with a Time" do
			result = described_class.
				from_hash( message: 'message', sender: 'sender', time: Time.at(1460569977) )
			expect( result.time.to_i ).to eq( 1460569977 )
		end


		it "can be constructed with a numeric time" do
			result = described_class.
				from_hash( message: 'message', sender: 'sender', time: 1460569977 )
			expect( result.time.to_i ).to eq( 1460569977 )
		end


		it "can be constructed with a string time" do
			result = described_class.
				from_hash( message: 'message', sender: 'sender', time: Time.at(1460569977).iso8601 )
			expect( result.time.to_i ).to eq( 1460569977 )
		end

	end

end

