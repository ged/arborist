#!/usr/bin/env rspec -cfd

require_relative '../spec_helper'

require 'arborist/monitor_runner'
require 'arborist/node/root'

describe Arborist::MonitorRunner do

	let( :req_socket ) { instance_double(ZMQ::Socket::Req) }

	let( :reactor ) { instance_double(CZTop::Reactor) }
	let( :runner ) { described_class.new }

	let( :monitor_class ) { Class.new(Arborist::Monitor) }

	let( :mon1 ) { monitor_class.new("testing monitor1", :testing) }
	let( :mon2 ) { monitor_class.new("testing monitor2", :testing) { splay 10 } }
	let( :mon3 ) { monitor_class.new("testing monitor3", :testing) }
	let( :monitors ) {[ mon1, mon2, mon3 ]}

		let( :node_tree ) {{
			'router' => {
				'addresses' => ['10.2.1.2', '1.2.3.4']
			},
			'server' => {
				'addresses' => ['10.2.1.118']
			}
		}}
		let( :ping_monitor_data ) {{
			'router' => {'ping' => { 'rtt' => 22 }},
			'server' => {'ping' => { 'rtt' => 8 }},
		}}


	before( :each ) do
		allow( CZTop::Reactor ).to receive( :new ).and_return( reactor )
		allow( reactor ).to receive( :register )
		allow( reactor ).to receive( :unregister )
	end


	it "can load monitors from an enumerator that yields Arborist::Monitors" do
		runner.load_monitors([ mon1, mon2, mon3 ])
		expect( runner.monitors ).to include( mon1, mon2, mon3 )
	end


	describe "a runner with loaded monitors" do

		it "registers its monitors to run on an interval and starts the ZMQ loop when run" do
			runner.monitors.replace([ mon1 ])

			expect( reactor ).to receive( :add_periodic_timer ).with( mon1.interval )
			expect( reactor ).to receive( :start_polling )

			runner.run
		end


		it "delays registration of its interval timer if a monitor has a splay" do
			runner.monitors.replace([ mon2 ])

			expect( reactor ).to receive( :add_oneshot_timer ).
				with( a_value_between(0, mon2.splay) ).and_yield
			expect( reactor ).to receive( :add_periodic_timer ).with( mon2.interval )
			expect( reactor ).to receive( :start_polling )

			runner.run
		end


		it "can run a monitor using async ZMQ IO" do

			# Set up the monitor's execution block with fixtured data
			mon1.exec do |nodes|
				ping_monitor_data
			end

			expect( reactor ).to receive( :event_enabled? ).with( runner.client.tree_api, :write ).
				at_least( :once ).
				and_return( true )


			fetch_request = instance_double( CZTop::Message )
			fetch_response = Arborist::TreeAPI.successful_response( node_tree )
			update_request = instance_double( CZTop::Message )
			update_response = Arborist::TreeAPI.successful_response( nil )

			expect( CZTop::Message ).to receive( :new ).and_return( fetch_request, update_request )
			expect( fetch_request ).to receive( :send_to ).with( runner.client.tree_api )
			expect( update_request ).to receive( :send_to ).with( runner.client.tree_api )
			expect( CZTop::Message ).to receive( :receive_from ).with( runner.client.tree_api ).
				and_return( fetch_response, update_response )
			expect( reactor ).to receive( :disable_events ).with( runner.client.tree_api, :write )

			runner.run_monitor( mon1 )

			# trigger the fetch request
			fetch_event = instance_double( CZTop::Reactor::Event,
				writable?: true, socket: runner.client.tree_api )
			runner.handle_io_event( fetch_event )

			# trigger the update request
			update_event = instance_double( CZTop::Reactor::Event,
				writable?: true, socket: runner.client.tree_api )
			runner.handle_io_event( update_event )
		end


		it "manages the communication between the monitor and the manager" do
			monitor = Arborist::Monitor.new do
				description 'test monitor'
				key :test
				every 20
				match type: 'host'
				use :addresses
				exec 'fping', '-e', '-t', '150'
			end
			nodes = { 'test1' => {}, 'test2' => {} }
			monitor_results = { 'test1' => {ping: {rtt: 1}}, 'test2' => {ping: {rtt: 8}} }

			expect( runner ).to receive( :fetch ).
				with( {type: 'host'}, false, [:addresses], {} ).
				and_yield( nodes )

			expect( monitor ).to receive( :run ).with( nodes ).
				and_return( monitor_results )

			expect( runner ).to receive( :update ).
				with({
					"test1"=>{:ping=>{:rtt=>1}, "_monitor_key"=>:test},
					"test2"=>{:ping=>{:rtt=>8}, "_monitor_key"=>:test}
				})

			runner.run_monitor( monitor )
		end

	end



end

