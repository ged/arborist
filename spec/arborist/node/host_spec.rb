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


	it "can be created with an IPAddr object" do
		result = described_class.new( 'testhost' ) do
			address IPAddr.new( '192.168.118.3' )
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


	it "can be created with address attributes" do
		result = described_class.new( 'testhost', addresses: '192.168.118.3' )
		expect( result.addresses ).to include( IPAddr.new('192.168.118.3') )
	end


	it "appends block address arguments to addresses in attributes" do
		result = described_class.new( 'testhost', addresses: '192.168.118.3' ) do
			address '127.0.0.1'
		end

		expect( result.addresses.length ).to eq( 2 )
		expect( result.addresses ).to include(
			IPAddr.new( '192.168.118.3' ),
			IPAddr.new( '127.0.0.1' )
		)
	end


	it "replaces its addresses when it's updated via #modify" do
		result = described_class.new( 'testhost' ) do
			address '192.168.118.3'
		end

		result.modify( addresses: ['192.168.28.2'] )

		expect( result.addresses ).to include( IPAddr.new('192.168.28.2') )
		expect( result.addresses ).to_not include( IPAddr.new('192.168.118.3') )
	end

	describe "matching" do

		let( :node ) do
			described_class.new( 'testhost' ) do
				address '192.168.66.12'
				address '10.2.12.68'
			end
		end


		it "can be matched with one of its addresses" do
			expect( node ).to match_criteria( address: '192.168.66.12' )
			expect( node ).to_not match_criteria( address: '127.0.0.1' )
		end


		it "can be matched with a netblock that includes one of its addresses" do
			expect( node ).to match_criteria( address: '192.168.66.0/24' )
			expect( node ).to match_criteria( address: '10.0.0.0/8' )
			expect( node ).to_not match_criteria( address: '192.168.66.64/27' )
			expect( node ).to_not match_criteria( address: '127.0.0.0/8' )
		end

	end

end

