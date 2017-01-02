#!/usr/bin/env rspec -cfd

require_relative '../spec_helper'

require 'arborist/monitor_runner'


describe Arborist::MonitorRunner do

	let( :zmq_loop ) { instance_double(ZMQ::Loop) }
	let( :req_socket ) { instance_double(ZMQ::Socket::Req) }
	let( :pollitem ) { instance_double(ZMQ::Pollitem) }

	let( :runner ) do
		obj = described_class.new
		obj.reactor = zmq_loop
		obj
	end

	let( :monitor_class ) { Class.new(Arborist::Monitor) }

	let( :mon1 ) { monitor_class.new("testing monitor1", :testing) }
	let( :mon2 ) { monitor_class.new("testing monitor2", :testing) { splay 10 } }
	let( :mon3 ) { monitor_class.new("testing monitor3", :testing) }
	let( :monitors ) {[ mon1, mon2, mon3 ]}


	it "can load monitors from an enumerator that yields Arborist::Monitors" do
		runner.load_monitors([ mon1, mon2, mon3 ])
		expect( runner.monitors ).to include( mon1, mon2, mon3 )
	end


	describe "a runner with loaded monitors" do

		before( :each ) do
			allow( zmq_loop ).to receive( :register ).with( an_instance_of(ZMQ::Pollitem) )
		end


		it "registers its monitors to run on an interval and starts the ZMQ loop when run" do
			runner.monitors.replace([ mon1 ])

			interval_timer = instance_double( ZMQ::Timer )
			expect( ZMQ::Timer ).to receive( :new ) do |i_delay, i_repeat, &i_block|
				expect( i_delay ).to eq( mon1.interval )
				expect( i_repeat ).to eq( 0 )

				expect( runner.handler ).to receive( :run_monitor ).with( mon1 )

				i_block.call
				interval_timer
			end

			expect( zmq_loop ).to receive( :register_timer ).with( interval_timer )
			expect( zmq_loop ).to receive( :start )

			runner.run
		end


		it "delays registration of its interval timer if a monitor has a splay" do
			runner.monitors.replace([ mon2 ])

			interval_timer = instance_double( ZMQ::Timer )
			expect( ZMQ::Timer ).to receive( :new ).with( mon2.interval, 0 ).
				and_return( interval_timer )

			timer = instance_double( ZMQ::Timer )
			expect( ZMQ::Timer ).to receive( :new ) do |delay, repeat, &block|
				expect( delay ).to be >= 0
				expect( delay ).to be <= mon2.splay
				expect( repeat ).to eq( 1 )

				block.call
				timer
			end

			expect( zmq_loop ).to receive( :register_timer ).with( interval_timer )
			expect( zmq_loop ).to receive( :register_timer ).with( timer )
			expect( zmq_loop ).to receive( :start )

			runner.run
		end

	end


	describe Arborist::MonitorRunner::Handler do

		let( :tree_api_handler ) { Arborist::Manager::TreeAPI.new(:pollable, :manager) }

		let( :handler ) { described_class.new( zmq_loop ) }

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


		it "can run a monitor using async ZMQ IO" do
			expect( zmq_loop ).to receive( :register ).with( handler.pollitem )

			# Queue up the monitor requests and register the socket as wanting to write
			mon1.exec do |nodes|
				ping_monitor_data
			end
			expect {
				handler.run_monitor( mon1 )
			}.to change { handler.registered? }.from( false ).to( true )

			# Fetch
			request = handler.client.make_fetch_request(
				mon1.positive_criteria,
				include_down: false,
				properties: mon1.node_properties
			)
			response = tree_api_handler.successful_response( node_tree )

			expect( handler.client.tree_api ).to receive( :send ).with( request )
			expect( handler.client.tree_api ).to receive( :recv ).and_return( response )

			expect {
				handler.on_writable
			}.to_not change { handler.registered? }

			# Update
			request = handler.client.make_update_request( ping_monitor_data )
			response = tree_api_handler.successful_response( nil )
			expect( handler.client.tree_api ).to receive( :send ).with( request )
			expect( handler.client.tree_api ).to receive( :recv ).and_return( response )

			# Unregister
			expect( zmq_loop ).to receive( :remove ).with( handler.pollitem )
			expect {
				handler.on_writable
			}.to change { handler.registered? }.from( true ).to( false )

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

			expect( handler ).to receive( :fetch ).
				with( {type: 'host'}, false, [:addresses], {} ).
				and_yield( nodes )

			expect( monitor ).to receive( :run ).with( nodes ).
				and_return( monitor_results )

			expect( handler ).to receive( :update ).
				with({
					"test1"=>{:ping=>{:rtt=>1}, "_monitor_key"=>:test},
					"test2"=>{:ping=>{:rtt=>8}, "_monitor_key"=>:test}
				})

			handler.run_monitor( monitor )
		end

	end

end

