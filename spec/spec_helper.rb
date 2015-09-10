# -*- ruby -*-
#encoding: utf-8

require 'pathname'
require 'simplecov' if ENV['COVERAGE']
require 'rspec'
require 'loggability/spechelpers'
require 'msgpack'

require 'arborist'
require 'arborist/manager'
require 'arborist/node'


class TestNode < Arborist::Node; end

class TestEvent < Arborist::Event; end


module Arborist::TestHelpers

	SPEC_DIR = Pathname( __FILE__ ).dirname
	SPEC_DATA_DIR = SPEC_DIR + 'data'

	TESTING_API_SOCK = 'inproc://arborist-api'
	TESTING_EVENT_SOCK = 'inproc://arborist-events'


	def self::included( mod )
		super

		mod.around( :each ) do |example|
			if example.metadata[:testing_manager]
				Loggability[ Arborist ].info "Configuring the manager to use testing ports."
				Arborist.configure({
					tree_api_url: TESTING_API_SOCK,
					event_api_url: TESTING_EVENT_SOCK,
				})

				example.run

				Arborist.configure
			else
				example.run
			end
		end
	end


	def make_testing_manager
		return Arborist.manager_for( SPEC_DATA_DIR + 'nodes' )
	end


	def pack_message( verb, *data )
		body = data.pop
		header = data.pop || {}
		header.merge!( action: verb, version: 1 )

		return MessagePack.pack([ header, body ])
	end


	def unpack_message( msg )
		return MessagePack.unpack( msg )
	end

end



RSpec.configure do |config|
	# include Arborist::TestHelpers

	SPEC_DIR = Pathname( __FILE__ ).dirname
	SPEC_DATA_DIR = SPEC_DIR + 'data'

	TESTING_API_SOCK = 'inproc://arborist-api'
	TESTING_EVENT_SOCK = 'inproc://arborist-events'

	config.run_all_when_everything_filtered = true
	config.filter_run :focus
	config.order = 'random'
	config.mock_with( :rspec ) do |mock|
		mock.syntax = :expect
	end

	config.include( Loggability::SpecHelpers )
	config.include( Arborist::TestHelpers )
end


