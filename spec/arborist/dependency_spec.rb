#!/usr/bin/env rspec -cfd

require_relative '../spec_helper'

require 'timecop'
require 'arborist/dependency'


describe Arborist::Dependency do


	it "can be constructed without identifiers" do
		result = described_class.new( :any )
		expect( result ).to be_empty
		expect( result.all_identifiers ).to be_empty
	end


	it "can be constructed with an operator and a list of identifiers" do
		result = described_class.new( :any, 'node1', 'node2' )
		expect( result ).to include( 'node1', 'node2' )
	end


	it "can be constructed with an operator and a list of other dependencies" do
		dep1 = described_class.new( :any, 'node1', 'node2' )
		dep2 = described_class.new( :any, 'node2', 'node3' )

		result = described_class.new( :all, dep1, dep2 )
		expect( result.subdeps ).to include( dep1, dep2 )
	end


	it "can be constructed with an operator and a list of both dependencies and identifiers" do
		dep1 = described_class.new( :any, 'node1', 'node2' )
		dep2 = described_class.new( :any, 'node2', 'node3' )

		result = described_class.new( :all, dep1, dep2, 'node4', 'node5' )
		expect( result.subdeps ).to include( dep1, dep2 )
		expect( result.identifiers ).to include( 'node4', 'node5' )
	end


	it "can return a Hash that describes itself" do
		dep1 = described_class.new( :any, 'node1', 'node2' )
		dep2 = described_class.new( :any, 'node2', 'node3' )
		dep3 = described_class.new( :all, dep1, dep2, 'node4', 'node5' )

		hash = dep3.to_h

		expect( hash ).to include( :behavior, :identifiers, :subdeps )

		expect( hash[:behavior] ).to eq( :all )
		expect( hash[:identifiers] ).to be_an( Array ).and( include('node4', 'node5') )
		expect( hash[:subdeps] ).to be_an( Array ).and( all be_a(Hash) )
		expect( hash[:subdeps] ).to all( include(:behavior, :identifiers, :subdeps) )
	end


	it "can be constructed from a nested Hash" do
		dep1 = described_class.new( :any, 'node1', 'node2' )
		dep2 = described_class.new( :any, 'node2', 'node3' )
		dep3 = described_class.new( :all, dep1, dep2, 'node4', 'node5' )

		clone = described_class.from_hash( dep3.to_h )

		expect( clone ).to eq( dep3 )
	end


	it "includes identifiers of all of its subdependencies" do
		dep1 = described_class.new( :any, 'node1', 'node2' )
		dep2 = described_class.new( :any, 'node2', 'node3' )

		result = described_class.new( :all, dep1, dep2, 'node4', 'node5' )
		expect( result.identifiers ).to include( 'node4', 'node5' )
		expect( result.identifiers ).to_not include( 'node1', 'node2', 'node3' )

		expect( result.all_identifiers.length ).to eq( 5 )
		expect( result ).to include( 'node1', 'node2', 'node3', 'node4', 'node5' )
	end


	it "can return the list of identifiers that have been marked down" do
		dep = described_class.new( :all, 'node1', 'node2', 'node3', 'node4', 'node5' )
		dep.mark_down( 'node1' )
		dep.mark_down( 'node4' )

		expect( dep.down_identifiers ).to include( 'node1', 'node4' )
		expect( dep.down_identifiers ).to_not include( 'node2', 'node3', 'node5' )
	end


	it "has a constructor for generating dependencies with a prefix" do
		result = described_class.on( :all, 'node1', 'node2', prefixes: ['host1', 'host2'] )
		expect( result ).to include( 'host1-node1', 'host1-node2', 'host2-node1', 'host2-node2' )
	end


	it "can mark one of its members as being down" do
		dep = described_class.new( :all, 'node1', 'node2' )
		dep.mark_down( 'node1' )

		expect( dep ).to be_down
		# down reason?
	end

	it "marks all downed dependencies with the same default timestamp" do
		dep1 = described_class.new( :all, 'node1', 'node2' )
		dep2 = described_class.new( :any, 'node1' )
		dep3 = described_class.new( :all, dep1, dep2 )
		dep3.mark_down( 'node1' )

		expect( dep1.identifier_states['node1'] ).to eq( dep2.identifier_states['node1'] )
	end


	it "marks all downed dependencies with the provided timestamp" do
		time = Time.parse( "2016-01-01 11:00:00" )
		dep1 = described_class.new( :all, 'node1', 'node2' )
		dep2 = described_class.new( :any, 'node1' )
		dep3 = described_class.new( :all, dep1, dep2 )
		dep3.mark_down( 'node1', time )

		expect( dep1.identifier_states['node1'] ).to eq( time )
		expect( dep2.identifier_states['node1'] ).to eq( time )
	end


	it "knows when the earliest dependency was marked down" do
		dep = described_class.new( :all, 'node1', 'node2', 'node3' )

		Timecop.freeze do
			dep.mark_down( 'node1' )
			earliest = Time.now

			Timecop.travel( 60 ) do
				dep.mark_down( 'node3' )

				expect( dep.earliest_down_time ).to eq( earliest )
			end
		end
	end


	it "returns nil if asked for the earliest down mark, and no nodes are maked down" do
		dep = described_class.new( :all, 'node1', 'node2', 'node3' )
		expect( dep.earliest_down_time ).to be_nil
	end


	it "knows when the latest dependency was marked down" do
		dep = described_class.new( :all, 'node1', 'node2', 'node3' )

		Timecop.freeze do
			dep.mark_down( 'node1' )

			Timecop.freeze( 60 ) do
				dep.mark_down( 'node3' )
				latest = Time.now

				expect( dep.latest_down_time ).to eq( latest )
			end
		end
	end


	it "returns nil if asked for the latest down mark, and no nodes are maked down" do
		dep = described_class.new( :all, 'node1', 'node2', 'node3' )
		expect( dep.latest_down_time ).to be_nil
	end


	it "propagates a node being marked down to its sub-dependencies" do
		dep1 = described_class.new( :all, 'node1', 'node2' )
		dep2 = described_class.new( :all, 'node2', 'node3' )
		dep3 = described_class.new( :any, 'node2', 'node5' )

		top_dep = described_class.new( :all, dep1, dep2, 'node4', dep3 )

		top_dep.mark_down( 'node2' )

		expect( dep1 ).to be_down
		expect( dep2 ).to be_down
		expect( dep3 ).to be_up
	end


	it "can return all of its sub-dependencies that are down" do
		dep1 = described_class.new( :all, 'node1', 'node2' )
		dep2 = described_class.new( :all, 'node2', 'node3' )
		dep3 = described_class.new( :any, 'node2', 'node5' )

		top_dep = described_class.new( :all, dep1, dep2, 'node4', dep3 )
		top_dep.mark_down( 'node2' )

		expect( top_dep.down_subdeps ).to include( dep1, dep2 )
		expect( top_dep.down_subdeps ).to_not include( dep3 )
	end


	it "can return all of its sub-dependencies that are up" do
		dep1 = described_class.new( :all, 'node1', 'node2' )
		dep2 = described_class.new( :all, 'node2', 'node3' )
		dep3 = described_class.new( :any, 'node2', 'node5' )

		top_dep = described_class.new( :all, dep1, dep2, 'node4', dep3 )
		top_dep.mark_down( 'node2' )

		expect( top_dep.up_subdeps ).to include( dep3 )
		expect( top_dep.up_subdeps ).to_not include( dep1, dep2 )
	end


	it "can iterate over its downed elements" do
		dep1 = described_class.new( :all, 'node1', 'node2' )
		dep2 = described_class.new( :all, 'node2', 'node3' )
		dep3 = described_class.new( :any, 'node2', 'node5' )

		top_dep = described_class.new( :all, 'node2', dep1, dep2, 'node4', dep3 )
		top_dep.mark_down( 'node2' )
		top_dep.mark_down( 'node5' )

		results = top_dep.each_downed.to_a
		expect( results.length ).to eq( 2 )
		expect( results[0] ).to include( 'node2', an_instance_of(Time) )
		expect( results[1] ).to include( 'node5', an_instance_of(Time) )
	end


	it "is equal to another node with the same identifiers" do
		dep1 = described_class.new( :all, 'node1', 'node2', 'node3' )
		dep2 = described_class.new( :all, 'node1', 'node2', 'node3' )
		dep3 = described_class.new( :all, 'node1', 'node2', 'node4' )

		expect( dep1 ).to eq( dep2 )
		expect( dep1 ).to_not eq( dep3 )
	end


	it "is equal to another node with the same identifiers and subdeps" do
		dep1 = described_class.new( :all, 'node1', 'node2', 'node3' )
		dep2 = described_class.new( :all, 'node4', 'node5', 'node6' )
		dep3 = described_class.new( :any, 'node4', 'node5', 'node6' )

		dep4 = described_class.new( :all, 'node1', dep1, dep2 )
		dep5 = described_class.new( :all, 'node1', dep1.dup, dep2.dup )
		dep6 = described_class.new( :all, 'node1', dep1, dep3 )
		dep7 = described_class.new( :all, 'node1', dep1, dep2, dep3 )

		expect( dep4 ).to eq( dep5 )
		expect( dep4 ).to_not eq( dep6 )
		expect( dep4 ).to_not eq( dep7 )
	end


	it "is eql? to another node with the same identifiers, subdeps, and state" do
		# The time values have to be the same too
		Timecop.freeze do
			dep1 = described_class.new( :all, 'node1', 'node2', 'node3' )
			dep2 = described_class.new( :all, 'node3', 'node4', 'node5' )

			dep4 = described_class.new( :all, 'node1', dep1, dep2 )
			dep4.mark_down( 'node2' )
			dep4.mark_down( 'node3' )

			dep5 = described_class.new( :all, 'node1', dep1.dup, dep2.dup )
			dep5.mark_down( 'node2' )
			dep5.mark_down( 'node3' )

			dep6 = described_class.new( :all, 'node1', dep1.dup, dep2.dup )
			dep6.mark_down( 'node2' )

			dep7 = described_class.new( :all, 'node1', dep1.dup, dep2.dup )
			dep7.mark_down( 'node2' )
			dep7.mark_down( 'node3' )
			dep7.mark_down( 'node4' )

			expect( dep4 ).to eql( dep5 )
			expect( dep4 ).to_not eql( dep6 )
			expect( dep4 ).to_not eql( dep7 )
		end
	end


	it "knows how to Marshal itself" do
		dep1 = described_class.new( :all, 'node1', 'node2' )
		dep2 = described_class.new( :all, 'node2', 'node3' )
		dep3 = described_class.new( :any, 'node2', 'node5' )

		top_dep = described_class.new( :all, dep1, dep2, 'node4', dep3 )

		expect( Marshal.load(Marshal.dump( top_dep )) ).to eq( top_dep )
	end


	# Mahlon's brain has a hard time with this.  Note for future Mahlon!
	# "This node depends on ALL of these other nodes to be up, for it to be up"
	# "This node depends on ANY of these other nodes to be up, for it to be up"

	# Another way to remember this:
	# ANY -> any of these is sufficient
	# ALL -> all of these are necessary

	describe "with 'all' behavior" do

		let( :dep ) { described_class.new(:all, 'node1', 'node2', 'node3') }


		it "is up if none of its members have been marked down" do
			expect( dep ).to be_up
		end


		it "is down if any of its members has been marked down" do
			expect {
				dep.mark_down( 'node2' )
			}.to change { dep.down? }.from( false ).to( true )
		end


		it "can describe the reason it's down" do
			dep.mark_down( 'node2' )
			expect( dep.down_reason ).to match( /node2 is unavailable as of/i )
		end


		it "can describe the reason if multiple nodes have been marked down" do
			dep.mark_down( 'node1' )
			dep.mark_down( 'node2' )
			# :FIXME: Does order matter in the 'all' case? This assumes no.
			expect( dep.down_reason ).to match( /node(1|2) \(and 1 other\) are unavailable as of/i )
		end


		it "can describe the reason if nodes in subdepedencies are down" do
			dep.subdeps << described_class.on( :any, 'node4', 'node5' )

			dep.mark_down( 'node1' )
			dep.mark_down( 'node4' )
			dep.mark_down( 'node5' )

			expect( dep.down_reason ).to match( /node1.*node4.*node5/i )
		end


		it "can describe the reason if only nodes in subdepedencies are down" do
			dep.subdeps << described_class.on( :any, 'node4', 'node5' )

			dep.mark_down( 'node4' )
			dep.mark_down( 'node5' )

			expect( dep.down_reason ).to match( /node4.*node5/i )
		end

	end


	describe "with 'any' behavior" do

		let( :dep ) { described_class.new(:any, 'node1', 'node2') }


		it "is up if none of its members have been marked down" do
			expect( dep ).to be_up
		end


		it "is up if only some of its members have been marked down" do
			expect {
				dep.mark_down( 'node2' )
			}.to_not change { dep.down? }
		end


		it "is down if all of its members have been marked down" do
			expect {
				dep.mark_down( 'node2' )
				dep.mark_down( 'node1' )
			}.to change { dep.down? }.from( false ).to( true )
		end


		it "can describe the reason it's down" do
			dep.mark_down( 'node2' )
			dep.mark_down( 'node1' )

			expect( dep.down_reason ).to match( /are all unavailable as of/i ).
				and( include('node1', 'node2') )
		end

	end



end

