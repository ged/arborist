#!/usr/bin/env rspec -cfd

require_relative '../../spec_helper'

require 'arborist/node/service'


describe Arborist::Node::Service do

	let( :host ) do
		Arborist::Node.create( 'host', 'testhost' ) do
			address '192.168.118.3'
		end
	end


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


	it "raises a sensible error when created without a host" do
		expect {
			described_class.new( 'dnsd', nil )
		}.to raise_error( Arborist::NodeError, /no host/i )
	end


	it "includes its service attributes when turned into a Hash" do
		service = described_class.new( 'dnsd', host, port: 53, protocol: 'udp', app_protocol: 'dns' )

		expect( service.to_h ).to include( :port, :protocol, :app_protocol )
		expect( service.to_h[:port] ).to eq( service.port )
		expect( service.to_h[:protocol] ).to eq( service.protocol )
		expect( service.to_h[:app_protocol] ).to eq( service.app_protocol )
	end


	it "keeps its service attributes when marshalled" do
		service = described_class.new( 'dnsd', host, port: 53, protocol: 'udp', app_protocol: 'dns' )

		expect( service.to_h ).to include( :port, :protocol, :app_protocol )
		expect( service.to_h[:port] ).to eq( service.port )
		expect( service.to_h[:protocol] ).to eq( service.protocol )
		expect( service.to_h[:app_protocol] ).to eq( service.app_protocol )
	end


	it "is equal to another service node with the same metadata and service attributes" do
		service1 = described_class.new( 'dnsd', host, port: 53, protocol: 'udp', app_protocol: 'dns' )
		service2 = described_class.new( 'dnsd', host, port: 53, protocol: 'udp', app_protocol: 'dns' )

		expect( service1 ).to eq( service2 )
	end


	it "is not equal to another service node with the same metadata and different service attributes" do
		service1 = described_class.new( 'dnsd', host, port: 53, protocol: 'udp', app_protocol: 'dns' )
		service2 = described_class.new( 'dnsd', host, port: 53, protocol: 'tcp', app_protocol: 'dns' )

		expect( service1 ).to_not eq( service2 )
	end


	it "is not equal to another service node with the same metadata and different port" do
		service1 = described_class.new( 'dnsd', host, port: 53, protocol: 'udp', app_protocol: 'dns' )
		service2 = described_class.new( 'dnsd', host, port: 80, protocol: 'udp', app_protocol: 'dns' )

		expect( service1 ).to_not eq( service2 )
	end


	it "is not equal to another service node with the same metadata and different app protocol" do
		service1 = described_class.new( 'dnsd', host, port: 53, protocol: 'udp', app_protocol: 'dns' )
		service2 = described_class.new( 'dnsd', host, port: 53, protocol: 'udp', app_protocol: 'smtp' )

		expect( service1 ).to_not eq( service2 )
	end



	describe "matching" do

		let( :host ) do
			Arborist::Node.create( 'host', 'testhost' ) do
				address '192.168.66.12'
				address '10.1.33.8'
			end
		end

		let( :node ) do
			described_class.new( 'ssh', host )
		end


		it "inherits its host's addresses" do
			expect( node ).to match_criteria( address: '192.168.66.12' )
			expect( node ).to_not match_criteria( address: '127.0.0.1' )
		end


		it "can be limited to a subset of its host's addresses" do
			node.address( host.addresses.first )
			expect( node ).to match_criteria( address: '192.168.66.12' )
			expect( node ).to_not match_criteria( address: '10.1.33.8' )
			expect( node ).to_not match_criteria( address: '127.0.0.1' )
		end


		it "errors if it specifies an address other than one of its host's addresses" do
			expect {
				node.address( '127.0.0.1' )
			}.to raise_error( Arborist::ConfigError, /127.0.0.1 is not one of testhost's addresses/i )
		end


		it "can be matched with a netblock that includes one of its host's addresses" do
			expect( node ).to match_criteria( address: '192.168.66.0/24' )
			expect( node ).to match_criteria( address: '10.0.0.0/8' )
			expect( node ).to_not match_criteria( address: '192.168.66.64/27' )
			expect( node ).to_not match_criteria( address: '127.0.0.0/8' )
		end


		it "can be matched with a port" do
			expect( node ).to match_criteria( port: 22 )
			expect( node ).to match_criteria( port: 'ssh' )
			expect( node ).to_not match_criteria( port: 80 )
			expect( node ).to_not match_criteria( port: 'www' )
			expect( node ).to_not match_criteria( port: 'chungwatch' )
		end


		it "can be matched with a protocol" do
			expect( node ).to match_criteria( protocol: 'tcp' )
			expect( node ).to_not match_criteria( protocol: 'udp' )
		end


		it "can be matched with an application protocol" do
			expect( node ).to match_criteria( app_protocol: 'ssh' )
			expect( node ).to match_criteria( app: 'ssh' )
			expect( node ).to_not match_criteria( app_protocol: 'http' )
			expect( node ).to_not match_criteria( app: 'http' )
		end

	end

end

