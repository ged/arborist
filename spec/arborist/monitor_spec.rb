#!/usr/bin/env rspec -cfd

require_relative '../spec_helper'

require 'arborist/monitor'


describe Arborist::Monitor do


	let( :trunk_node ) do
		testing_node( 'trunk' ) do
			properties['pork'] = 'nope'
		end
	end
	let( :branch_node ) do
		testing_node( 'branch', 'trunk' ) do
			properties['pork'] = 'yes'
		end
	end
	let( :leaf_node ) do
		testing_node( 'leaf', 'branch' ) do
			properties['pork'] = 'twice'
		end
	end


	let( :testing_nodes ) {{
		'trunk' => trunk_node.to_h,
		'branch' => branch_node.to_h,
		'leaf' => leaf_node.to_h
	}}


	it "can be created with just a description and key" do
		mon = described_class.new( "the description", :key )
		expect( mon ).to be_a( described_class )
		expect( mon.description ).to eq( "the description" )
		expect( mon.key ).to eq( :key )
		expect( mon.include_down? ).to be_falsey
		expect( mon.interval ).to eq( Arborist::Monitor::DEFAULT_INTERVAL )
		expect( mon.splay ).to eq( 0 )
		expect( mon.positive_criteria ).to be_empty
		expect( mon.negative_criteria ).to be_empty
		expect( mon.node_properties ).to be_empty
	end


	it "can be created with just a description and key set in the block" do
		mon = described_class.new do
			description "the description"
			key :key
		end

		expect( mon ).to be_a( described_class )
		expect( mon.description ).to eq( "the description" )
		expect( mon.key ).to eq( :key )
		expect( mon.include_down? ).to be_falsey
		expect( mon.interval ).to eq( Arborist::Monitor::DEFAULT_INTERVAL )
		expect( mon.splay ).to eq( 0 )
		expect( mon.positive_criteria ).to be_empty
		expect( mon.negative_criteria ).to be_empty
		expect( mon.node_properties ).to be_empty
	end


	it "can be created with description set in the constructor and key in the block" do
		mon = described_class.new( "the description" ) do
			key :key
		end

		expect( mon ).to be_a( described_class )
		expect( mon.description ).to eq( "the description" )
		expect( mon.key ).to eq( :key )
		expect( mon.include_down? ).to be_falsey
		expect( mon.interval ).to eq( Arborist::Monitor::DEFAULT_INTERVAL )
		expect( mon.splay ).to eq( 0 )
		expect( mon.positive_criteria ).to be_empty
		expect( mon.negative_criteria ).to be_empty
		expect( mon.node_properties ).to be_empty
	end


	it "can be created with a DSL function" do
		mon = Arborist::Monitor( "the description", :the_key )

		expect( mon ).to be_a( described_class )
		expect( mon.description ).to eq( "the description" )
		expect( mon.key ).to eq( :the_key )
		expect( mon.include_down? ).to be_falsey
		expect( mon.interval ).to eq( Arborist::Monitor::DEFAULT_INTERVAL )
		expect( mon.splay ).to eq( 0 )
		expect( mon.positive_criteria ).to be_empty
		expect( mon.negative_criteria ).to be_empty
		expect( mon.node_properties ).to be_empty
	end


	it "raises a ConfigError if constructed without a description" do
		expect {
			described_class.new do
				key :key
			end
		}.to raise_error( Arborist::ConfigError, /no description/i )
	end


	it "raises a ConfigError if constructed without a key" do
		expect {
			described_class.new( "the description" )
		}.to raise_error( Arborist::ConfigError, /no key/i )
	end


	it "yields itself to the provided block for the DSL" do
		block_self = nil
		mon = described_class.new( "testing monitor", :testing ) do
			block_self = self
		end

		expect( block_self ).to be( mon )
	end


	it "can specify an interval" do
		mon = described_class.new( "testing monitor", :testing ) do
			every 30
		end

		expect( mon.interval ).to eq( 30 )
	end


	it "can specify a splay" do
		mon = described_class.new( "testing monitor", :testing ) do
			splay 15
		end

		expect( mon.splay ).to eq( 15 )
	end


	it "can specify criteria for matching nodes to monitor" do
		mon = described_class.new( "testing monitor", :testing ) do
			match type: 'host'
		end

		expect( mon.positive_criteria ).to include( type: 'host' )
	end


	it "can specify criteria for matching nodes not to monitor" do
		mon = described_class.new( "testing monitor", :testing ) do
			exclude tag: 'laptop'
		end

		expect( mon.negative_criteria ).to include( tag: 'laptop' )
	end


	it "automatically includes 'down' nodes if the matcher specifies an unreachable state" do
		mon = described_class.new( "testing monitor", :testing ) do
			match status: 'down'
		end

		expect( mon.include_down? ).to be_truthy
	end


	it "can specify that it will include hosts marked as 'down'" do
		mon = described_class.new( "testing monitor", :testing ) do
			include_down true
		end

		expect( mon.include_down? ).to be_truthy
	end


	it "can specify one or more properties to include in the input to the monitor" do
		mon = described_class.new( "testing monitor", :testing ) do
			use :address, :tags
		end

		expect( mon.node_properties ).to include( :address, :tags )
	end


	it "can specify a command to exec to do the monitor's work" do
		mon = described_class.new( "the description", :testing ) do
			exec 'cat'
		end

		output = mon.run( testing_nodes )
		expect( output ).to be_a( Hash )
		expect( output ).to include( *(testing_nodes.keys) )
	end


	it "can specify a block to call to do the monitor's work" do
		block_was_run = false

		mon = described_class.new( "the description", :testing )
		mon.exec do |nodes|
			block_was_run = true
		end

		mon.run( testing_nodes )

		expect( block_was_run ).to be_truthy
	end


	it "can specify a runnable object to do the monitor's work" do
		mod = Module.new do
			class << self; attr_accessor :was_run ; end
			@was_run = false

			def self::run( nodes )
				self.was_run = true
			end
		end


		mon = described_class.new( "the description", :testing )
		mon.exec( mod )

		mon.run( testing_nodes )

		expect( mod.was_run ).to be_truthy
	end


	it "uses node properties specified by the runnable object if it provides them" do
		mod = Module.new do
			class << self; attr_accessor :was_run ; end
			@was_run = false

			def self::run( nodes )
				self.was_run = true
			end

			def self::node_properties
				%i[ uri http_method body mimetype ]
			end
		end

		mon = described_class.new( "the description", :testing )
		mon.exec( mod )

		expect( mon.node_properties ).to include( :uri, :http_method, :body, :mimetype )
	end


	it "can provide a function for building arguments for its command" do
		mon = described_class.new( "the description", :testing ) do

			exec 'the_command'

			handle_results {|*| }
			exec_input {|*| }
			exec_arguments do |nodes|
				Loggability[ Arborist ].debug "In the argument-builder."
				nodes.keys
			end
		end

		expect( Process ).to receive( :spawn ) do |*args|
			options = args.pop

			expect( args ).to eq([ 'the_command', 'trunk', 'branch', 'leaf' ])
			expect( options ).to be_a( Hash )
			expect( options ).to include( :in, :out, :err )

			nil
		end

		mon.run( testing_nodes )
	end


	it "handles system call errors while running the monitor command" do
		mon = described_class.new( "the description", :testing ) do

			exec 'the_command'

			handle_results {|*| }
			exec_input {|*| }
			exec_arguments do |nodes|
				Loggability[ Arborist ].debug "In the argument-builder."
				nodes.keys
			end
		end

		expect( Process ).to receive( :spawn ) do |*args|
			raise Errno::EPIPE, "broken pipe"
		end

		expect {
			mon.run( testing_nodes )
		}.to_not raise_error
	end


	it "can provide a function for providing input to its command" do
		mon = described_class.new( "the description", :testing ) do

			exec 'cat'

			exec_input do |nodes, writer|
				writer.puts( nodes.keys )
			end
			handle_results do |pid, out, err|
				return out.readlines.map( &:chomp )
			end
		end

		results = mon.run( testing_nodes )

		expect( results ).to eq( testing_nodes.keys )
	end


	it "can provide a function for parsing its command's output" do
		mon = described_class.new( "the description", :testing ) do

			exec 'cat'

			exec_arguments {|*| }
			exec_input do |nodes, writer|
				writer.puts( nodes.keys )
			end
			handle_results do |pid, out, err|
				out.readlines.map( &:chomp ).map( &:upcase )
			end
		end

		results = mon.run( testing_nodes )

		expect( results ).to eq( testing_nodes.keys.map(&:upcase) )
	end


	it "can provide a Module that implements its exec callbacks" do
		the_module = Module.new do

			def exec_input( nodes, writer )
				writer.puts( nodes.keys )
			end

			def handle_results( pid, out, err )
				err.flush
				return out.each_line.with_object({}) do |line, accum|
					accum[ line.chomp ] = { echoed: 'yep' }
				end
			end

		end

		mon = described_class.new( "the description", :testing ) do
			exec 'cat'
			exec_callbacks( the_module )
		end

		results = mon.run( testing_nodes )

		expect( results ).to be_a( Hash )
		expect( results.size ).to eq( 3 )
		expect( results ).to include( *testing_nodes.keys )
		expect( results['trunk'] ).to eq({ echoed: 'yep' })
		expect( results['branch'] ).to eq({ echoed: 'yep' })
		expect( results['leaf'] ).to eq({ echoed: 'yep' })
	end

end

