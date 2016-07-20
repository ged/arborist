#!/usr/bin/env rspec -cfd

require_relative '../spec_helper'

require 'arborist/observer_runner'


describe Arborist::ObserverRunner do


	let( :zmq_loop ) { instance_double(ZMQ::Loop) }
	let( :req_socket ) { instance_double(ZMQ::Socket::Req) }
	let( :sub_socket ) { instance_double(ZMQ::Socket::Sub) }
	let( :pollitem ) { instance_double(ZMQ::Pollitem) }

	let( :runner ) do
		obj = described_class.new
		obj.reactor = zmq_loop
		obj
	end

	let( :observer_class ) { Class.new(Arborist::Observer) }

	let( :observer1 ) { observer_class.new("testing observer1") }
	let( :observer2 ) { observer_class.new("testing observer2") }
	let( :observer3 ) { observer_class.new("testing observer3") }
	let( :observers ) {[ observer1, observer2, observer3 ]}


	it "can load observers from an enumerator that yields Arborist::Observers" do
		runner.load_observers([ observer1, observer2, observer3 ])
		expect( runner.observers ).to include( observer1, observer2, observer3 )
	end


	describe "a runner with loaded observers" do

		before( :each ) do
			allow( zmq_loop ).to receive( :register ).with( an_instance_of(ZMQ::Pollitem) )
		end


		xit "subscribes to events for each of its observers and starts the ZMQ loop when run" do
			expect( Arborist.zmq_context ).to receive( :socket ).
				with( :REQ ).and_return( req_socket )
			expect( Arborist.zmq_context ).to receive( :socket ).
				with( :SUB ).and_return( sub_socket )

			expect( req_socket ).to receive( :subscribe ).with(  )
		end

	end


	describe Arborist::ObserverRunner::Handler

end

