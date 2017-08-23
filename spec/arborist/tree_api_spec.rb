#!/usr/bin/env rspec -cfd

require_relative '../spec_helper'

require 'arborist/tree_api'

describe Arborist::TreeAPI, :testing_manager do

	it "can encode a valid Tree API header and body into a message" do
		result = described_class.encode( {version: 1}, foo: 'bar' )
		expect( result ).to be_a( CZTop::Message )

		payload = result.frames.first.to_s
		expect( payload ).to be_a_messagepacked( Array )

		decoded = MessagePack.unpack( payload )
		expect( decoded.first ).to eq({ 'version' => 1 })
		expect( decoded.last ).to eq({ 'foo' => 'bar' })
	end


	it "can encode a valid Tree API header and a nil body into a message" do
		result = described_class.encode( {version: 1}, nil )
		expect( result ).to be_a( CZTop::Message )

		payload = result.frames.first.to_s
		expect( payload ).to be_a_messagepacked( Array )

		decoded = MessagePack.unpack( payload )
		expect( decoded.first ).to eq({ 'version' => 1 })
		expect( decoded.last ).to be_nil
	end


	it "raises an exception if the header to encode isn't a Hash" do
		expect {
			described_class.encode( 1 )
		}.to raise_error( Arborist::MessageError, /header is not a Map/i )
	end


	it "raises an exception if the body is invalid" do
		expect {
			described_class.encode( {version: 1}, ['foo'] )
		}.to raise_error( Arborist::MessageError, /invalid message.*body must be/i )
	end


	it "can build a valid Tree API request message" do
		result = described_class.request( :status )
		expect( result ).to be_a( CZTop::Message )

		payload = result.frames.first.to_s
		expect( payload ).to be_a_messagepacked( Array )

		decoded = MessagePack.unpack( payload )
		expect( decoded.first ).to eq({
			'version' => described_class::PROTOCOL_VERSION,
			'action' => 'status'
		})
		expect( decoded.last ).to be_nil
	end


	it "can build a valid success response message" do
		result = described_class.successful_response( foo: 'bar' )
		expect( result ).to be_a( CZTop::Message )

		payload = result.frames.first.to_s
		expect( payload ).to be_a_messagepacked( Array )

		decoded = MessagePack.unpack( payload )
		expect( decoded.first ).to include( 'success' => true )
		expect( decoded.last ).to eq({ 'foo' => 'bar' })
	end


	it "can build a valid error response message" do
		result = described_class.error_response( 'category', 'reason' )
		expect( result ).to be_a( CZTop::Message )

		payload = result.frames.first.to_s
		expect( payload ).to be_a_messagepacked( Array )

		decoded = MessagePack.unpack( payload )
		expect( decoded.first['success'] ).to eq( false )
		expect( decoded.first['category'] ).to eq( 'category' )
		expect( decoded.first['reason'] ).to eq( 'reason' )
	end


	it "can decode a header and payload from a valid request message" do
		payload = [
			{ 'version' => described_class::PROTOCOL_VERSION },
			{ 'foo' => 'bar' }
		]
		msg = CZTop::Message.new( MessagePack.pack(payload) )

		header, body = described_class.decode( msg )

		expect( header ).to eq( payload.first )
		expect( body ).to eq( payload.last )
	end


	describe "raises an exception when decoding a request message" do

		it "from a different protocol version" do
			payload = [
				{ 'version' => described_class::PROTOCOL_VERSION.succ },
				{ 'foo' => 'bar' }
			]
			msg = CZTop::Message.new( MessagePack.pack(payload) )

			expect {
				described_class.decode( msg )
			}.to raise_error( Arborist::MessageError, /unknown protocol version/i )
		end


		it "that doesn't contain a valid MessagePack payload'" do
			msg = CZTop::Message.new( 'some random junk' )

			expect {
				described_class.decode( msg )
			}.to raise_error( Arborist::MessageError, /invalid message/i )
		end

	end


end

