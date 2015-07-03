#!/usr/bin/env rspec -cfd

require_relative '../spec_helper'

require 'arborist/monitor'


describe Arborist::Monitor do


	it "can be created with just a description" do
		mon = described_class.new( "the description" )
		expect( mon ).to be_a( described_class )
		expect( mon.description ).to eq( "the description" )
		expect( mon.include_down? ).to be_falsey
		expect( mon.interval ).to eq( Arborist::Monitor::DEFAULT_INTERVAL )
		expect( mon.splay ).to eq( 0 )
		expect( mon.positive_criteria ).to be_empty
		expect( mon.negative_criteria ).to be_empty
		expect( mon.node_properties ).to be_empty
		expect( mon.run_callback ).to be_nil
		expect( mon.run_command ).to be_nil
	end


	it "yields itself to the provided block for the DSL" do
		block_self = nil
		mon = described_class.new( "testing monitor" ) do
			block_self = self
		end

		expect( block_self ).to be( mon )
	end


	it "can specify an interval" do
		mon = described_class.new( "testing monitor" ) do
			every 30
		end

		expect( mon.interval ).to eq( 30 )
	end


	it "can specify a splay" do
		mon = described_class.new( "testing monitor" ) do
			splay 15
		end

		expect( mon.splay ).to eq( 15 )
	end


	it "can specify criteria for matching nodes to monitor" do
		mon = described_class.new( "testing monitor" ) do
			match type: 'host'
		end

		expect( mon.positive_criteria ).to include( type: 'host' )
	end


	it "can specify criteria for matching nodes not to monitor" do
		mon = described_class.new( "testing monitor" ) do
			exclude tag: 'laptop'
		end

		expect( mon.negative_criteria ).to include( tag: 'laptop' )
	end


	it "can specify that it will include hosts marked as 'down'" do
		mon = described_class.new( "testing monitor" ) do
			include_down true
		end

		expect( mon.include_down? ).to be_truthy
	end


	it "can specify one or more properties to include in the input to the monitor" do
		mon = described_class.new( "testing monitor" ) do
			use :address, :tags
		end

		expect( mon.node_properties ).to include( :address, :tags )
	end


	it "can specify a command to exec to do the monitor's work" do
		mon = described_class.new( "the description" ) do
			exec 'fping'
		end

		expect( mon.run_callback ).to be_nil
		expect( mon.run_command ).to eq([ 'fping' ])
	end


	it "can specify a block to call to do the monitor's work" do
		block_was_run = false

		mon = described_class.new( "the description" ) do
			exec do |nodes|
				block_was_run = true
			end
		end

		expect( mon.run_command ).to be_nil
		expect( mon.run_callback ).to be_a( Proc )
		expect { mon.run_callback.call({}) }.to change { block_was_run }.to( true )
	end


	it "can specify a command to exec with a block to wrap it in to do the monitor's work" do
		mon = described_class.new( "the description" ) do
			exec( 'fping' ) do |nodes|
				# ...
			end
		end

		expect( mon.run_command ).to eq( ['fping'] )
		expect( mon.run_callback ).to be_a( Proc )
	end


end

