#!/usr/bin/env rspec -cfd

require_relative '../../spec_helper'

require 'arborist/node/service'


describe Arborist::Node::Service do

	let( :host ) { Arborist::Node.create(:host, 'server') }


	it "can be created without reasonable defaults based on its identifier" do
		result = described_class.new( 'ssh', host )
		expect( result.port ).to eq( 22 )
		expect( result.protocol ).to eq( 'tcp' )
	end


	it "can be created with an explicit port" do
		result = described_class.new( 'ssh', host, port: 2222 )
		expect( result.port ).to eq( 2222 )
		expect( result.protocol ).to eq( 'tcp' )
	end


	it "can be created with an explicit port" do
		result = described_class.new( 'rsspk', host, port: 1801, protocol: 'udp' )
		expect( result.port ).to eq( 1801 )
		expect( result.protocol ).to eq( 'udp' )
	end


	it "uses the identifier as the application protocol if none is specified" do
		result = described_class.new( 'rsspk', host, port: 1801 )
		expect( result.port ).to eq( 1801 )
		expect( result.app_protocol ).to eq( 'rsspk' )
	end


	it "can specify an explicit application protocol" do
		result = described_class.new( 'dnsd', host, port: 53, protocol: 'udp', app_protocol: 'dns' )
		expect( result.app_protocol ).to eq( 'dns' )
	end

end

