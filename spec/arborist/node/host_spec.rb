#!/usr/bin/env rspec -cfd

require_relative '../../spec_helper'

require 'arborist/node/host'


describe Arborist::Node::Host do

	it "can be created without any addresses" do
		result = described_class.new( 'testhost' )
		expect( result.addresses ).to be_empty
	end


	it "can be created with a single IPv4 address" do
		result = described_class.new( 'testhost' ) do
			address '192.168.118.3'
		end

		expect( result.addresses ).to eq([ IPAddr.new('192.168.118.3') ])
	end


	it "can be created with a single hostname with an IPv4 address" do
		expect( TCPSocket ).to receive( :gethostbyname ).with( 'arbori.st' ).
			and_return(['arbori.st', [], Socket::AF_INET, '198.145.180.85'])

		result = described_class.new( 'arborist' ) do
			address 'arbori.st'
		end

		expect( result.addresses.size ).to eq( 1 )
		expect( result.addresses ).to include( IPAddr.new('198.145.180.85') )
	end


	it "can be created with a single hostname with both an IPv4 and an IPv6 address" do
		expect( TCPSocket ).to receive( :gethostbyname ).with( 'google.com' ).
			and_return(["google.com", [], 2, "216.58.216.174", "2607:f8b0:400a:807::200e"])

		result = described_class.new( 'google' ) do
			address 'google.com'
		end

		expect( result.addresses.size ).to eq( 2 )
		expect( result.addresses ).to include( IPAddr.new('216.58.216.174') )
		expect( result.addresses ).to include( IPAddr.new('2607:f8b0:400a:807::200e') )
	end


	it "can be created with multiple hostnames with IPv4 addresses" do
		expect( TCPSocket ).to receive( :gethostbyname ).with( 'arbori.st' ).
			and_return(['arbori.st', [], Socket::AF_INET, '198.145.180.85'])
		expect( TCPSocket ).to receive( :gethostbyname ).with( 'faeriemud.org' ).
			and_return(['faeriemud.org', [], Socket::AF_INET, '198.145.180.86'])

		result = described_class.new( 'arborist' ) do
			address 'arbori.st'
			address 'faeriemud.org'
		end

		expect( result.addresses.size ).to eq( 2 )
		expect( result.addresses ).to include( IPAddr.new('198.145.180.85') )
		expect( result.addresses ).to include( IPAddr.new('198.145.180.86') )
	end

end

