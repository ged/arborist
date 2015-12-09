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


	it "can specify an action to run when a subscribed event is received" do
		observer = described_class.new( "testing observer" ) do
			action do |uuid, event|
				puts( uuid )
			end
		end

		expect( observer.actions ).to be_an( Array )
		expect( observer.actions.length ).to eq( 1 )
	end


	it "can specify more than one action to run when a subscribed event is received" do
		observer = described_class.new( "testing observer" ) do
			action do |uuid, event|
				puts( uuid )
			end
			action do |uuid, event|
				$stderr.puts( uuid )
			end
		end

		expect( observer.actions ).to be_an( Array )
		expect( observer.actions.length ).to eq( 2 )
	end

end

