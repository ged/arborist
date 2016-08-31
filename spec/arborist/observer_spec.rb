#!/usr/bin/env rspec -cfd

require_relative '../spec_helper'

describe Arborist::Observer do


	it "can be created with just a description" do
		observer = described_class.new( "the description" )
		expect( observer ).to be_a( described_class )
		expect( observer.description ).to eq( "the description" )
	end


	it "yields itself to the provided block for the DSL" do
		block_self = nil
		observer = described_class.new( "testing observer" ) do
			block_self = self
		end

		expect( block_self ).to be( observer )
	end


	it "can specify a subscription for an event it's interested in" do
		observer = described_class.new( "testing observer" ) do
			subscribe to: 'node.delta'
		end

		expect( observer.subscriptions ).to be_an( Array )
		expect( observer.subscriptions.length ).to eq( 1 )
	end


	it "can specify a subscription for more than one event it's interested in" do
		observer = described_class.new( "testing observer" ) do
			subscribe to: 'node.delta'
			subscribe to: 'sys.reload'
		end

		expect( observer.subscriptions ).to be_an( Array )
		expect( observer.subscriptions.length ).to eq( 2 )
	end


	it "can specify criteria for events" do
		observer = described_class.new( "testing observer" ) do
			subscribe to: 'node.up', where: { type: 'host' }
		end

		expect( observer.subscriptions ).to be_an( Array )
		expect( observer.subscriptions ).to include( a_hash_including(criteria: {type: 'host'}) )
		expect( observer.subscriptions.length ).to eq( 1 )
	end


	it "can specify negative criteria for events" do
		observer = described_class.new( "testing observer" ) do
			subscribe to: 'node.up', exclude: { type: 'host' }
		end

		expect( observer.subscriptions ).to be_an( Array )
		expect( observer.subscriptions ).to include( a_hash_including(exclude: {type: 'host'}) )
		expect( observer.subscriptions.length ).to eq( 1 )
	end


	it "can specify a subscription node other than the root" do
		observer = described_class.new( "testing observer" ) do
			subscribe to: 'node.down', on: 'dmz-gateway'
		end

		expect( observer.subscriptions ).to be_an( Array )
		expect( observer.subscriptions ).to include( a_hash_including(identifier: 'dmz-gateway') )
		expect( observer.subscriptions.length ).to eq( 1 )
	end


	it "can specify an action to run when a subscribed event is received" do
		observer = described_class.new( "testing observer" ) do
			action do |event|
				# no-op
			end
		end

		expect( observer.actions ).to be_an( Array )
		expect( observer.actions.length ).to eq( 1 )
	end


	it "can specify more than one action to run when a subscribed event is received" do
		observer = described_class.new( "testing observer" ) do
			action do |event|
				# no-op
			end
			action do |event|
				# no-op
			end
		end

		expect( observer.actions ).to be_an( Array )
		expect( observer.actions.length ).to eq( 2 )
		expect( observer.actions ).to all( be_a(Arborist::Observer::Action) )
	end


	it "can specify a summary action" do
		observer = described_class.new( "testing observer" ) do
			summarize( every: 5 ) do |events|
				# no-op
			end
		end

		expect( observer.actions ).to be_an( Array )
		expect( observer.actions.length ).to eq( 1 )
		expect( observer.actions.first ).to be_a( Arborist::Observer::Summarize )
	end


	it "can specify a mix of regular and summary actions" do
		observer = described_class.new( "testing observer" ) do
			summarize( every: 5 ) do |events|
				# no-op
			end
			action do |event|
				# no-op
			end
		end

		expect( observer.actions ).to be_an( Array )
		expect( observer.actions.length ).to eq( 2 )
		expect( observer.actions.first ).to be_a( Arborist::Observer::Summarize )
		expect( observer.actions.last ).to be_a( Arborist::Observer::Action )
	end


	it "passes events it is given to handle to its actions" do
		observer = described_class.new( "testing observer" ) do
			summarize( every: 5 ) do |events|
				# no-op
			end
			action do |event|
				# no-op
			end
		end

		event = {}
		expect( observer.actions.first ).to receive( :handle_event ).with( event )
		expect( observer.actions.last ).to receive( :handle_event ).with( event )

		observer.handle_event( "eventid", event )
	end


	it "can build a list of timer callbacks for its actions" do
		summarize_called = false

		observer = described_class.new( "testing observer" ) do
			summarize( every: 5 ) do |events|
				summarize_called = true
			end
			action do |event|
				# no-op
			end
		end

		results = observer.timers

		expect( results ).to be_an( Array )
		expect( results.size ).to eq( 1 )
		expect( results ).to all( be_an(Array) )
		expect( results.last[0] ).to eq( 5 )

		observer.handle_event( "eventid", {} )
		expect { results.last[1].call }.to change { summarize_called }.to( true )
	end

end

