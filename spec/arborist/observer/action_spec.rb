#!/usr/bin/env rspec -cfd

require_relative '../../spec_helper'

require 'timecop'
require 'arborist/observer/action'


using Arborist::TimeRefinements


describe Arborist::Observer::Action do

	let( :event ) {{ stuff: :woo }}


	it "can be created with just a block" do
		result = described_class.new {}
		expect( result ).to be_a( described_class )
		expect( result.block ).to respond_to( :call )
	end


	it "is supplied the event history if the block has a second argument" do
		history_arg = nil
		action = described_class.new( after: 2 ) do |event, history|
			history_arg = history
		end

		action.handle_event( event )
		action.handle_event( event )

		expect( history_arg ).to be_a( Hash )
	end


	it "clears the event history when the block is called" do
		action = described_class.new( after: 2 ) {}
		2.times { action.handle_event(event) }

		expect( action.event_history ).to be_empty
	end


	it "requires a block" do
		expect { described_class.new }.to raise_exception( ArgumentError, /requires a block/i )
	end


	context "without any other criteria" do

		before( :each ) do
			@call_count = 0
			@last_call_arguments = nil
		end

		let( :action ) do
			described_class.new do |args|
				@call_count += 1
				@last_call_arguments = args
			end
		end


		it "calls its block immediately when handling an event" do
			expect { action.handle_event(event) }.to change { @call_count }.by( 1 ).and(
				change { @last_call_arguments }.to( event )
			)
		end


	end


	# within: 0, after: 1, during: nil


	context "with a time threshold" do

		before( :each ) do
			@call_count = 0
			@last_call_arguments = nil
		end

		let( :action ) do
			described_class.new( within: 1.minute ) do |args|
				@call_count += 1
				@last_call_arguments = args
			end
		end


		it "calls its block if two events arrive within the specified time" do
			Timecop.freeze do
				expect { action.handle_event(event) }.to_not change { @call_count }
				Timecop.travel( 5.seconds ) do
					expect { action.handle_event(event) }.to change { @call_count }.by( 1 )
				end
			end
		end


		it "calls its block if three events arrive, and the last two are within the specified time" do
			Timecop.freeze do
				expect { action.handle_event(event) }.to_not change { @call_count }
				Timecop.travel( 65.seconds ) do
					expect { action.handle_event(event) }.to_not change { @call_count }
					Timecop.travel( 5.seconds ) do
						expect { action.handle_event(event) }.to change { @call_count }.by( 1 )
					end
				end
			end
		end


		it "doesn't call its block if two events arrive with more than the specified time between them" do
			Timecop.freeze do
				expect { action.handle_event(event) }.to_not change { @call_count }
				Timecop.travel( 65.seconds ) do
					expect { action.handle_event(event) }.to_not change { @call_count }
				end
			end
		end


		context "and a count threshold" do

			let( :action ) do
				described_class.new( within: 1.minute, after: 3 ) do |args|
					@call_count += 1
					@last_call_arguments = args
				end
			end

			it "calls its block if the threshold number of events arrive within the specified time" do
				Timecop.freeze do
					expect { action.handle_event(event) }.to_not change { @call_count }
					Timecop.travel( 5.seconds ) do
						expect { action.handle_event(event) }.to_not change { @call_count }
						Timecop.travel( 5.seconds ) do
							expect { action.handle_event(event) }.to change { @call_count }.by( 1 )
						end
					end
				end
			end


			it "doesn't call the block if the threshold number of events arrive with more than " +
			   "the specified time between them" do
				Timecop.freeze do
					expect { action.handle_event(event) }.to_not change { @call_count }
					Timecop.travel( 5.seconds ) do
						expect { action.handle_event(event) }.to_not change { @call_count }
						Timecop.travel( 65.seconds ) do
							expect { action.handle_event(event) }.to_not change { @call_count }
						end
					end
				end
			end

		end

	end


	context "with a count threshold" do
		before( :each ) do
			@call_count = 0
			@last_call_arguments = nil
		end

		let( :action ) do
			described_class.new( after: 2 ) do |args|
				@call_count += 1
				@last_call_arguments = args
			end
		end


		it "calls the block if more events than count threshold have arrived" do
			expect { action.handle_event(event) }.to_not change { @call_count }
			expect { action.handle_event(event) }.to change { @call_count }.by( 1 )
		end

	end


	context "with a schedule" do


		context "with a time threshold" do

			context "and a count threshold"

		end


		context "and a count threshold"

	end


end


