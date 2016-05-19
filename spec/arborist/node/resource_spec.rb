#!/usr/bin/env rspec -cfd

require_relative '../../spec_helper'

require 'arborist/node/resource'


describe Arborist::Node::Resource do

	let( :host ) do
		Arborist::Node.create( 'host', 'testhost' ) do
			address '192.168.118.3'
		end
	end


	it "can be created without reasonable defaults based on its identifier" do
		result = described_class.new( 'disk', host )
		expect( result.identifier ).to eq( "testhost-disk" )
	end


	it "raises a sensible error when created without a host" do
		expect {
			described_class.new( 'load', nil )
		}.to raise_error( Arborist::NodeError, /no host/i )
	end

	describe "matching" do

		let( :host ) do
			Arborist::Node.create( 'host', 'testhost' ) do
				address '192.168.66.12'
				address '10.1.33.8'
			end
		end

		let( :node ) do
			described_class.new( 'disk', host )
		end


		it "can be matched with one of its host's addresses" do
			expect( node ).to match_criteria( address: '192.168.66.12' )
			expect( node ).to_not match_criteria( address: '127.0.0.1' )
		end

		it "can be matched with a netblock that includes one of its host's addresses" do
			expect( node ).to match_criteria( address: '192.168.66.0/24' )
			expect( node ).to match_criteria( address: '10.0.0.0/8' )
			expect( node ).to_not match_criteria( address: '192.168.66.64/27' )
			expect( node ).to_not match_criteria( address: '127.0.0.0/8' )
		end
	end
end

