#!/usr/bin/env rspec -cfd

require_relative 'spec_helper'

require 'pathname'
require 'arborist'


describe Arborist do

	before( :all ) do
		@original_config_env = ENV[Arborist::CONFIG_ENV]
	end

	before( :each ) do
		ENV.delete(Arborist::CONFIG_ENV)
	end

	after( :each ) do
		Arborist::Node::Root.reset
	end

	after( :all ) do
		ENV[Arborist::CONFIG_ENV] = @original_config_env
	end


	it "has a semantic version" do
		expect( described_class::VERSION ).to match( /^\d+\.\d+\.\d+/ )
	end


	describe "configurability", log: :fatal do

		before( :each ) do
			Configurability.configure_objects( Configurability.default_config )
		end

		after( :all ) do
			Configurability.reset
		end


		it "can return the loaded configuration" do
			expect( described_class.config ).to be( Configurability.loaded_config )
		end


		it "knows whether or not the config has been loaded" do
			expect( described_class ).to be_config_loaded
			Configurability.reset
			expect( described_class ).to_not be_config_loaded
		end


		it "will load a local config file if it exists and none is specified" do
			config_object = double( "Configurability::Config object" )
			allow( config_object ).to receive( :[] ).with( :arborist ).and_return( {} )

			expect( Configurability ).to receive( :gather_defaults ).
				and_return( {} )
			expect( Arborist::LOCAL_CONFIG_FILE ).to receive( :exist? ).
				and_return( true )
			expect( Configurability::Config ).to receive( :load ).
				with( Arborist::LOCAL_CONFIG_FILE, {} ).
				and_return( config_object )
			expect( config_object ).to receive( :install )

			Arborist.load_config
		end


		it "will load a default config file if none is specified and there's no local config" do
			config_object = double( "Configurability::Config object" )
			allow( config_object ).to receive( :[] ).with( :arborist ).and_return( {} )

			expect( Configurability ).to receive( :gather_defaults ).
				and_return( {} )
			expect( Arborist::LOCAL_CONFIG_FILE ).to receive( :exist? ).
				and_return( false )
			expect( Configurability::Config ).to receive( :load ).
				with( Arborist::DEFAULT_CONFIG_FILE, {} ).
				and_return( config_object )
			expect( config_object ).to receive( :install )

			Arborist.load_config
		end


		it "will load a config file given in an environment variable" do
			ENV['ARBORIST_CONFIG'] = '/usr/local/etc/config.yml'

			config_object = double( "Configurability::Config object" )
			allow( config_object ).to receive( :[] ).with( :arborist ).and_return( {} )

			expect( Configurability ).to receive( :gather_defaults ).
				and_return( {} )
			expect( Configurability::Config ).to receive( :load ).
				with( '/usr/local/etc/config.yml', {} ).
				and_return( config_object )
			expect( config_object ).to receive( :install )

			Arborist.load_config
		end


		it "will load a config file and install it if one is given" do
			config_object = double( "Configurability::Config object" )
			allow( config_object ).to receive( :[] ).with( :arborist ).and_return( {} )

			expect( Configurability ).to receive( :gather_defaults ).
				and_return( {} )
			expect( Configurability::Config ).to receive( :load ).
				with( 'a/configfile.yml', {} ).
				and_return( config_object )
			expect( config_object ).to receive( :install )

			Arborist.load_config( 'a/configfile.yml' )
		end


		it "will override default values when loading the config if they're given" do
			config_object = double( "Configurability::Config object" )
			allow( config_object ).to receive( :[] ).with( :arborist ).and_return( {} )

			expect( Configurability ).to_not receive( :gather_defaults )
			expect( Configurability::Config ).to receive( :load ).
				with( 'a/different/configfile.yml', {database: {dbname: 'test'}} ).
				and_return( config_object )
			expect( config_object ).to receive( :install )

			Arborist.load_config( 'a/different/configfile.yml', database: {dbname: 'test'} )
		end

	end


	it "can construct a Manager for all nodes provided by a Loader" do
		loader = instance_double( Arborist::Loader )
		expect( loader ).to receive( :nodes ).and_return([
			testing_node('trunk'),
			testing_node('branch', 'trunk'),
			testing_node('leaf', 'branch')
		])

		expect( described_class.manager_for(loader) ).to be_a( Arborist::Manager )
	end


	it "can construct a MonitorRunner for all monitors provided by a Loader" do
		loader = instance_double( Arborist::Loader )
		expect( loader ).to receive( :monitors ).and_return([
			:a_monitor,
			:another_monitor
		])

		expect( described_class.monitor_runner_for(loader) ).to be_a( Arborist::MonitorRunner )
	end


	it "can construct an ObserverRunner for all observers provided by a Loader" do
		loader = instance_double( Arborist::Loader )
		expect( loader ).to receive( :observers ).and_return([
			:an_observer,
			:another_observer
		])

		expect( described_class.observer_runner_for(loader) ).to be_a( Arborist::ObserverRunner )
	end


	it "has a ZMQ context" do
		expect( described_class.zmq_context ).to be_a( ZMQ::Context )
	end

end

