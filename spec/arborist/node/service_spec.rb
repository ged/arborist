#!/usr/bin/env rspec -cfd

require_relative '../../spec_helper'

require 'arborist/node/service'


describe Arborist::Node::Service do

	it "can be created without reasonable defaults based on its identifier" do
		result = described_class.new( 'ssh' )
		expect( result.port ).to eq( 22 )
		expect( result.protocol ).to eq( 'tcp' )
	end


	it "can be created with an explicit port" do
		result = described_class.new( 'ssh', port: 2222 )
		expect( result.port ).to eq( 2222 )
		expect( result.protocol ).to eq( 'tcp' )
	end


	it "can be created with an explicit port" do
		result = described_class.new( 'rsspk', port: 1801, protocol: 'udp' )
		expect( result.port ).to eq( 1801 )
		expect( result.protocol ).to eq( 'udp' )
	end

end

