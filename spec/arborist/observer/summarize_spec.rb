#!/usr/bin/env rspec -cfd

require_relative '../../spec_helper'

require 'timecop'
require 'arborist/observer/summarize'


using Arborist::TimeRefinements


describe Arborist::Observer::Summarize do

	let( :event ) {{ stuff: :woo }}


	it "can be created with just a block and a count" do
		result = described_class.new( every: 1.minute ) {}
		expect( result ).to be_a( described_class )
		expect( result.block ).to respond_to( :call )
		expect( result.time_threshold ).to eq( 1.minute )
	end


	it "errors if created with just a block" do
		expect {
			described_class.new {}
		}.to raise_error( ArgumentError, /requires a value/i )
	end


	it "is supplied the event history if the block has a second argument" do
		history_arg = nil
		summarize = described_class.new( count: 2 ) do |history|
			history_arg = history
		end

		summarize.handle_event( event )
		summarize.handle_event( event )

		expect( history_arg ).to be_a( Hash )
	end


	it "clears the event history when the block is called" do
		summarize = described_class.new( count: 2 ) {}
		2.times { summarize.handle_event(event) }

		expect( summarize.event_history ).to be_empty
	end


	it "requires a block" do
		expect {
			described_class.new( count: 2 )
		}.to raise_exception( ArgumentError, /requires a block/i )
	end



	# every: 0, count: 1, during: nil


	context "with a time threshold" do

		before( :each ) do
			@call_count = 0
			@last_call_arguments = nil
		end

		let( :summarize ) do
			described_class.new( every: 1.minute ) do |args|
				@call_count += 1
				@last_call_arguments = args
			end
		end


		it "calls its block if any events have arrived within the specified time" do
			Timecop.freeze do
				expect { summarize.handle_event(event) }.to_not change { @call_count }
				Timecop.travel( 5.seconds ) do
					expect { summarize.handle_event(event) }.to_not change { @call_count }
					Timecop.travel( 55.seconds ) do
						expect { summarize.on_timer }.to change { @call_count }.by( 1 )
					end
				end
			end
		end


		it "doesn't call its block if no events arrive with the specified time" do
			expect { summarize.on_timer }.to_not change { @call_count }
		end


		context "and a count threshold" do

			let( :summarize ) do
				described_class.new( every: 1.minute, count: 3 ) do |args|
					@call_count += 1
					@last_call_arguments = args
				end
			end

			it "calls its block if the threshold number of events arrive before the specified time threshold" do
				Timecop.freeze do
					expect { summarize.handle_event(event) }.to_not change { @call_count }
					Timecop.travel( 5.seconds ) do
						expect { summarize.handle_event(event) }.to_not change { @call_count }
						Timecop.travel( 5.seconds ) do
							expect { summarize.handle_event(event) }.to change { @call_count }.by( 1 )
						end
					end
				end
			end


			it "calls the block if the time threshold is met before the count threshold" do
				Timecop.freeze do
					expect { summarize.handle_event(event) }.to_not change { @call_count }
					Timecop.travel( 5.seconds ) do
						expect { summarize.handle_event(event) }.to_not change { @call_count }
						Timecop.travel( 55.seconds ) do
							expect { summarize.on_timer }.to change { @call_count }
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

		let( :summarize ) do
			described_class.new( count: 2 ) do |args|
				@call_count += 1
				@last_call_arguments = args
			end
		end


		it "calls the block if more events than count threshold have arrived" do
			expect { summarize.handle_event(event) }.to_not change { @call_count }
			expect { summarize.handle_event(event) }.to change { @call_count }.by( 1 )
		end

	end


	context "with a schedule" do


		context "with a time threshold" do

			context "and a count threshold"

		end


		context "and a count threshold"

	end


end


