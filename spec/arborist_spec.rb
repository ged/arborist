#!/usr/bin/env rspec -cfd

require_relative 'spec_helper'

require 'pathname'
require 'arborist'


describe Arborist do

	before( :all ) do
		@original_config_env = ENV[Arborist::CONFIG_ENV]
		@data_dir = Pathname( __FILE__ ).dirname + 'data'
	end

	before( :each ) do
		ENV.delete(Arborist::CONFIG_ENV)
	end

	after( :all ) do
		ENV[Arborist::CONFIG_ENV] = @original_config_env
	end


	it "has a semantic version" do
		expect( described_class::VERSION ).to match( /^\d+\.\d+\.\d+/ )
	end


	describe "configurability" do

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


	it "can load all nodes in a directory and return a manager for them" do
		expect( described_class.manager_for(@data_dir) ).to be_a( Arborist::Manager )
	end


	it "has a ZMQ context" do
		ctx = instance_double( ZMQ::Context )
		expect( ZMQ::Context ).to receive( :new ).once.and_return( ctx )

		expect( described_class.zmq_context ).to be( ctx )
		expect( described_class.zmq_context ).to be( ctx )
	end

end

