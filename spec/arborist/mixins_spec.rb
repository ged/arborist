#!/usr/bin/env rspec -cfd

require_relative '../spec_helper'

require 'timecop'

require 'arborist/mixins'


describe Arborist, "mixins" do

	describe Arborist::MethodUtilities, 'used to extend a class' do

		let!( :extended_class ) do
			klass = Class.new
			klass.extend( Arborist::MethodUtilities )
			klass
		end

		it "can declare a class-level attribute reader" do
			extended_class.singleton_attr_reader :foo
			expect( extended_class ).to respond_to( :foo )
			expect( extended_class ).to_not respond_to( :foo= )
			expect( extended_class ).to_not respond_to( :foo? )
		end

		it "can declare a class-level attribute writer" do
			extended_class.singleton_attr_writer :foo
			expect( extended_class ).to_not respond_to( :foo )
			expect( extended_class ).to respond_to( :foo= )
			expect( extended_class ).to_not respond_to( :foo? )
		end

		it "can declare a class-level attribute reader and writer" do
			extended_class.singleton_attr_accessor :foo
			expect( extended_class ).to respond_to( :foo )
			expect( extended_class ).to respond_to( :foo= )
			expect( extended_class ).to_not respond_to( :foo? )
		end

		it "can declare a class-level alias" do
			def extended_class.foo
				return "foo"
			end
			extended_class.singleton_method_alias( :bar, :foo )

			expect( extended_class.bar ).to eq( 'foo' )
		end

		it "can declare an instance attribute predicate method" do
			extended_class.attr_predicate :foo
			instance = extended_class.new

			expect( instance ).to_not respond_to( :foo )
			expect( instance ).to_not respond_to( :foo= )
			expect( instance ).to respond_to( :foo? )

			expect( instance.foo? ).to be_falsey

			instance.instance_variable_set( :@foo, 1 )
			expect( instance.foo? ).to be_truthy
		end

		it "can declare an instance attribute predicate and writer" do
			extended_class.attr_predicate_accessor :foo
			instance = extended_class.new

			expect( instance ).to_not respond_to( :foo )
			expect( instance ).to respond_to( :foo= )
			expect( instance ).to respond_to( :foo? )

			expect( instance.foo? ).to be_falsey

			instance.foo = 1
			expect( instance.foo? ).to be_truthy
		end

		it "can declare a class-level attribute predicate and writer" do
			extended_class.singleton_predicate_accessor :foo
			expect( extended_class ).to_not respond_to( :foo )
			expect( extended_class ).to respond_to( :foo= )
			expect( extended_class ).to respond_to( :foo? )
		end


		it "can declare a class-level predicate method" do
			extended_class.singleton_predicate_reader :foo
			expect( extended_class ).to_not respond_to( :foo )
			expect( extended_class ).to_not respond_to( :foo= )
			expect( extended_class ).to respond_to( :foo? )
		end


		it "can declare an instance DSLish accessor" do
			extended_class.dsl_accessor( :foo )
			instance = extended_class.new

			instance.foo( 13 )
			expect( instance.foo ).to eq( 13 )
		end


		it "the instance DSLish accessor works with a `false` argument" do
			extended_class.dsl_accessor( :foo )
			instance = extended_class.new

			instance.foo( false )
			expect( instance.foo ).to equal( false )
		end

	end


	describe Arborist::TimeRefinements do

		using( described_class )

		context "used to extend Time objects" do

			it "makes them aware of whether they're in the future or not" do
				Timecop.freeze do
					time = Time.now
					expect( time.future? ).to be_falsey

					future_time = time + 1
					expect( future_time.future? ).to be_truthy

					past_time = time - 1
					expect( past_time.future? ).to be_falsey
				end
			end


			it "makes them aware of whether they're in the past or not" do
				Timecop.freeze do
					time = Time.now
					expect( time.past? ).to be_falsey

					future_time = time + 1
					expect( future_time.past? ).to be_falsey

					past_time = time - 1
					expect( past_time.past? ).to be_truthy
				end
			end


			it "adds the ability to express themselves as an offset in English" do
				Timecop.freeze do
					expect( 1.second.ago.as_delta ).to eq( 'less than a minute ago' )
					expect( 1.second.from_now.as_delta ).to eq( 'less than a minute from now' )

					expect( 1.minute.ago.as_delta ).to eq( 'a minute ago' )
					expect( 1.minute.from_now.as_delta ).to eq( 'a minute from now' )
					expect( 68.seconds.ago.as_delta ).to eq( 'a minute ago' )
					expect( 68.seconds.from_now.as_delta ).to eq( 'a minute from now' )
					expect( 2.minutes.ago.as_delta ).to eq( '2 minutes ago' )
					expect( 2.minutes.from_now.as_delta ).to eq( '2 minutes from now' )
					expect( 38.minutes.ago.as_delta ).to eq( '38 minutes ago' )
					expect( 38.minutes.from_now.as_delta ).to eq( '38 minutes from now' )

					expect( 1.hour.ago.as_delta ).to eq( 'about an hour ago' )
					expect( 1.hour.from_now.as_delta ).to eq( 'about an hour from now' )
					expect( 75.minutes.ago.as_delta ).to eq( 'about an hour ago' )
					expect( 75.minutes.from_now.as_delta ).to eq( 'about an hour from now' )

					expect( 2.hours.ago.as_delta ).to eq( '2 hours ago' )
					expect( 2.hours.from_now.as_delta ).to eq( '2 hours from now' )
					expect( 14.hours.ago.as_delta ).to eq( '14 hours ago' )
					expect( 14.hours.from_now.as_delta ).to eq( '14 hours from now' )

					expect( 22.hours.ago.as_delta ).to eq( 'about a day ago' )
					expect( 22.hours.from_now.as_delta ).to eq( 'about a day from now' )
					expect( 28.hours.ago.as_delta ).to eq( 'about a day ago' )
					expect( 28.hours.from_now.as_delta ).to eq( 'about a day from now' )

					expect( 36.hours.ago.as_delta ).to eq( '2 days ago' )
					expect( 36.hours.from_now.as_delta ).to eq( '2 days from now' )
					expect( 4.days.ago.as_delta ).to eq( '4 days ago' )
					expect( 4.days.from_now.as_delta ).to eq( '4 days from now' )

					expect( 1.week.ago.as_delta ).to eq( 'about a week ago' )
					expect( 1.week.from_now.as_delta ).to eq( 'about a week from now' )
					expect( 8.days.ago.as_delta ).to eq( 'about a week ago' )
					expect( 8.days.from_now.as_delta ).to eq( 'about a week from now' )

					expect( 15.days.ago.as_delta ).to eq( '2 weeks ago' )
					expect( 15.days.from_now.as_delta ).to eq( '2 weeks from now' )
					expect( 3.weeks.ago.as_delta ).to eq( '3 weeks ago' )
					expect( 3.weeks.from_now.as_delta ).to eq( '3 weeks from now' )

					expect( 1.month.ago.as_delta ).to eq( '4 weeks ago' )
					expect( 1.month.from_now.as_delta ).to eq( '4 weeks from now' )
					expect( 36.days.ago.as_delta ).to eq( '5 weeks ago' )
					expect( 36.days.from_now.as_delta ).to eq( '5 weeks from now' )

					expect( 6.months.ago.as_delta ).to eq( '6 months ago' )
					expect( 6.months.from_now.as_delta ).to eq( '6 months from now' )
					expect( 14.months.ago.as_delta ).to eq( '14 months ago' )
					expect( 14.months.from_now.as_delta ).to eq( '14 months from now' )

					expect( 6.year.ago.as_delta ).to eq( '6 years ago' )
					expect( 6.year.from_now.as_delta ).to eq( '6 years from now' )
					expect( 14.years.ago.as_delta ).to eq( '14 years ago' )
					expect( 14.years.from_now.as_delta ).to eq( '14 years from now' )
				end
			end

		end

	end

end

