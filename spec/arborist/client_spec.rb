#!/usr/bin/env rspec -cfd

require_relative '../spec_helper'

require 'arborist/client'


describe Arborist::Client, :testing_manager do

	before( :each ) do
		Arborist.reset_zmq_context

		@manager = make_testing_manager()
		@manager_thread = Thread.new do
			Thread.current.abort_on_exception = true
			manager.run
			Loggability[ Arborist ].info "Stopped the test manager"
		end

		count = 0
		until manager.running? || count > 30
			sleep 0.1
			count += 1
		end
		raise "Manager didn't start up" unless manager.running?
	end

	after( :each ) do
		@manager.stop
		@manager_thread.join

		count = 0
		while @manager.zmq_loop.running? || count > 30
			sleep 0.1
			Loggability[ Arborist ].info "ZMQ loop still running"
			count += 1
		end
		raise "ZMQ Loop didn't stop" if @manager.zmq_loop.running?
	end


	let( :manager ) { @manager }
	let( :client ) { described_class.new }


	it "can fetch the status of the manager it's connected to" do
		res = client.status
		expect( res ).to include( 'server_version', 'state', 'uptime', 'nodecount' )
	end

end

