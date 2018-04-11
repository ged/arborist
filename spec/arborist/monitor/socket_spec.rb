#!/usr/bin/env rspec -cfd

require_relative '../../spec_helper'

require 'arborist'
require 'arborist/node/host'
require 'arborist/node/service'
require 'arborist/monitor/socket'


describe Arborist::Monitor::Socket do

	describe 'TCP' do

		let( :described_class ) { Arborist::Monitor::Socket::TCP }

		let( :host_node ) do
			Arborist::Node.create( 'host', 'test' ) do
				description "Test host node with a few TCP services"
				address '192.168.26.1'

				tags :testing
			end
		end

		let( :default_timeout ) { described_class::DEFAULT_OPTIONS[:timeout] }

		let( :www_service_node ) { host_node.service('www') }
		let( :ssh_service_node ) { host_node.service('ssh') }
		let( :nat_pmp_service_node ) { host_node.service('nat-pmp', port: 5351) }

		let( :service_nodes ) {[ www_service_node, ssh_service_node, nat_pmp_service_node ]}
		let( :service_nodes_hash ) do
			service_nodes.each_with_object({}) do |node, accum|
				accum[ node.identifier ] = node.fetch_values
			end
		end


		# it_behaves_like "an Arborist Monitor"


		def sockaddr_for( node )
			return Socket.sockaddr_in( node.port, node.addresses.first.to_s )
		end


		def make_successful_mock_socket( node )
			address = Addrinfo.tcp( node.addresses.first.to_s, node.port )
			socket = instance_double( Socket, "#{node.identifier} socket", remote_address: address )

			expect( socket ).to receive( :connect_nonblock ).with( sockaddr_for(node) ).
				and_raise( IO::EINPROGRESSWaitWritable )
			allow( socket ).to receive( :getpeername ).
				and_return( address.to_sockaddr )

			return socket
		end


		def make_initial_error_mock_socket( node, error_class, message )
			address = Addrinfo.tcp( node.addresses.first.to_s, node.port )
			socket = instance_double( Socket, "#{node.identifier} socket", remote_address: address )

			expect( socket ).to receive( :connect_nonblock ).
				with( sockaddr_for(node) ).
				and_raise( error_class.new(message) )

			return socket
		end


		def make_wait_error_mock_socket( node, error_class, message )
			address = Addrinfo.tcp( node.addresses.first.to_s, node.port )
			socket = instance_double( Socket, "#{node.identifier} socket", remote_address: address )

			expect( socket ).to receive( :connect_nonblock ).with( sockaddr_for(node) ).
				and_raise( IO::EINPROGRESSWaitWritable )
			expect( socket ).to receive( :getpeername ).
				and_raise( Errno::EINVAL.new("Invalid argument - getpeername(2)") )
			expect( socket ).to receive( :read ).with( 1 ).
				and_raise( Errno::ECONNREFUSED.new )

			return socket
		end


		it "opens TCP connections to the ports of the nodes" do
			fake_sockets = service_nodes.map do |node|
				make_successful_mock_socket( node )
			end

			expect( Socket ).to receive( :new ).and_return( *fake_sockets )
			expect( IO ).to receive( :select ).
				with( nil, fake_sockets, nil, kind_of(Numeric) ).
				and_return( [nil, fake_sockets, nil] )

			expect( fake_sockets ).to all( receive( :close ) )

			result = described_class.run( service_nodes_hash )

			expect( result ).to be_a( Hash )
			expect( result ).to include( *service_nodes.map(&:identifier) )
			expect( result.values ).to all( include(
				tcp_socket_connect: a_hash_including(:duration)
			) )
		end


		it "updates nodes with an error on a SocketError" do
			socket = make_initial_error_mock_socket( www_service_node, SocketError,
				"getaddrinfo: nodename nor servname provided, or not known" )
			allow( Socket ).to receive( :new ).and_return( socket )

			result = described_class.run( 'test-www' => www_service_node.fetch_values )

			expect( result ).to be_a( Hash )
			expect( result ).to include( 'test-www' )
			expect(
				result['test-www']
			).to include( error: 'getaddrinfo: nodename nor servname provided, or not known' )
		end


		it "updates nodes with an error if the connection times out" do
			socket = make_successful_mock_socket( www_service_node )
			allow( Socket ).to receive( :new ).and_return( socket )
			allow( socket ).to receive( :close )
			allow( IO ).to receive( :select ) do
				sleep 0.2
				[nil, nil, nil]
			end

			result = described_class.new( timeout: 0.1 ).
				run( 'test-www' => www_service_node.fetch_values )

			expect( result ).to be_a( Hash )
			expect( result ).to include( 'test-www' )
			expect( result['test-www'] ).to include( error: 'Timeout after 0.100s' )
		end


		it "updates nodes with an error on a 'connection refused' error" do
			socket = make_initial_error_mock_socket( www_service_node, Errno::ECONNREFUSED,
				"the message" )
			allow( Socket ).to receive( :new ).and_return( socket )

			result = described_class.run( 'test-www' => www_service_node.fetch_values )

			expect( result ).to be_a( Hash )
			expect( result ).to include( 'test-www' )
			expect( result['test-www'] ).to include( error: 'Connection refused - the message' )
		end


		it "updates nodes with an error on a 'host unreachable' error" do
			socket = make_initial_error_mock_socket( www_service_node, Errno::EHOSTUNREACH,
				"the message" )
			allow( Socket ).to receive( :new ).and_return( socket )

			result = described_class.run( 'test-www' => www_service_node.fetch_values )

			expect( result ).to be_a( Hash )
			expect( result ).to include( 'test-www' )
			expect( result['test-www'] ).to include( error: 'No route to host - the message' )
		end


		it "can be instantiated to run with a different timeout" do
			mon = described_class.new.with_timeout( 30 )
			expect( mon.timeout ).to eq( 30 )
		end

	end

end


