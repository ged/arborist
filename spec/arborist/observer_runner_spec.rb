#!/usr/bin/env rspec -cfd

require_relative '../spec_helper'

require 'rspec/wait'
require 'cztop'
require 'cztop/reactor'

require 'arborist/observer_runner'


describe Arborist::ObserverRunner do

	before( :each ) do
		$emails = []
		$texts = []
	end

	after( :each ) do
		$emails.clear
		$texts.clear
	end


	let( :observer1 ) do
		Arborist::Observer "Email on ack/disabled/enabled" do
			subscribe to: 'node.acked'
			subscribe to: 'node.disabled'
			subscribe to: 'node.enabled'

			action do |event|
				$emails << event
			end

		end
	end
	let( :observer2 ) do
		Arborist::Observer "SMS on nodes down" do
			subscribe to: 'node.down'
			action do |event|
				$texts << event
			end
		end
	end
	let( :observer3 ) do
		Arborist::Observer 'Email on disk full' do
			subscribe to: 'node.down',
				where: { type: 'resource', category: 'disk' }
			action do |event|
				$emails << event
			end
		end
	end

	let( :observers ) {[ observer1, observer2, observer3 ]}


	it "can load observers from an enumerator that yields Arborist::Observers" do
		runner = described_class.new
		runner.load_observers([ observer1, observer2, observer3 ])
		expect( runner.observers ).to include( observer1, observer2, observer3 )
	end


	describe "a runner with loaded observers", :testing_manager do

		before( :each ) do
			@manager_thread = Thread.new do
				@manager = make_testing_manager()
				Thread.current.abort_on_exception = true
				@manager.run
				Loggability[ Arborist ].info "Stopped the test manager"
			end

			count = 0
			until (@manager && @manager.running?) || count > 30
				sleep 0.1
				count += 1
			end
			raise "Manager didn't start up" unless @manager.running?
		end

		after( :each ) do
			@manager.simulate_signal( :TERM )
			@manager_thread.join

			count = 0
			while @manager.running? || count > 30
				sleep 0.1
				Loggability[ Arborist ].info "Manager still running"
				count += 1
			end
			raise "Manager didn't stop" if @manager.running?
		end


		let( :runner ) do
			runner = described_class.new
			runner.load_observers( observers )
			runner
		end


		it "subscribes for each of its observers and listens for events when run" do
			thr = Thread.new { runner.run }
			wait( 3 ).for { runner }.to be_running

			expect( @manager.subscriptions.length ).to eq( runner.subscriptions.length + 1 )

			runner.simulate_signal( :TERM )
			thr.join( 2 )
			thr.kill
		end


		it "runs the observers when subscribed events are sent"

	end

end

