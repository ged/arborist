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

end

