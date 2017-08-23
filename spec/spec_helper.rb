# -*- ruby -*-
#encoding: utf-8

require 'pathname'
require 'simplecov' if ENV['COVERAGE']
require 'rspec'
require 'rspec/wait'
require 'loggability/spechelpers'
require 'msgpack'

require 'arborist'
require 'arborist/manager'
require 'arborist/node'
require 'arborist/mixins'


class TestNode < Arborist::Node; end

class TestSubNode < Arborist::Node
	parent_type :test
end

class TestEvent < Arborist::Event; end


RSpec::Matchers.define( :match_criteria ) do |criteria|
	match do |node|
		criteria = Arborist::HashUtilities.stringify_keys( criteria )
		node.matches?( criteria )
	end
end


class BeMessagepacked

	def initialize( expected_type )
		@expected_type = expected_type
		@actual_value = nil
		@decoded = nil
		@exception = nil
	end


	def matches?( actual_value )
		@actual_value = actual_value
		@decoded = MessagePack.unpack( actual_value )
		return @decoded.is_a?( @expected_type )
	rescue => err
		@exception = err
		return false
	end


	def failure_reason
		if @exception && @exception.is_a?( MessagePack::MalformedFormatError )
			return "it was not formatted correctly: %s" % [ @exception.message ]
		elsif @exception
			return "there was a %p when trying to decode it: %s" %
				[ @exception.class, @exception.message ]
		elsif @decoded && !@decoded.is_a?( @expected_type )
			return "it was a msgpacked %p" % [ @decoded.class ]
		else
			return 'there was an unknown problem'
		end
	end


	def failure_message
		"expected %p to be a msgpacked %p but %s" % [ @actual_value, @expected_type, self.failure_reason ]
	end


	def failure_message_when_negated
		"expected %p not to be a msgpacked %p, but it was" % [ @actual_value, @actual_value ]
	end

end


module Arborist::TestConstants
	SPEC_DIR = Pathname( __FILE__ ).dirname
	SPEC_DATA_DIR = SPEC_DIR + 'data'

	TESTING_API_SOCK = "inproc://arborist-api"
	TESTING_EVENT_SOCK = "inproc://arborist-events"
end

module Arborist::TestHelpers

	include Arborist::TestConstants

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

				File.unlink( TESTING_EVENT_SOCK ) if File.exist?( TESTING_EVENT_SOCK )
				File.unlink( TESTING_API_SOCK ) if File.exist?( TESTING_API_SOCK )
			else
				example.run
			end
		end
	end


	def make_testing_manager
		Arborist::Manager.linger = 0
		loader = Arborist::Loader.create( :file, SPEC_DATA_DIR + 'nodes' )
		return Arborist.manager_for( loader )
	end



	#
	# Fixture Functions
	#

	def node_subclass
		@node_subclass ||= Class.new( Arborist::Node )
	end


	def testing_node( identifier, parent=nil, &block )
		node = node_subclass.new( identifier, &block )
		node.parent( parent ) if parent
		return node
	end


	#
	# Expectations
	#

	### Set an expectation that the receiving value is an instance of the
	### +expected_class+ that's been encoded with msgpack.
	def be_a_messagepacked( expected_class )
		return BeMessagepacked.new( expected_class )
	end

end



RSpec.configure do |config|
	include Arborist::TestConstants

	config.run_all_when_everything_filtered = true
	config.filter_run :focus
	config.order = 'random'
	config.mock_with( :rspec ) do |mock|
		mock.syntax = :expect
	end

	config.after( :each ) do
		Arborist::Node::Root.reset
	end

	config.filter_run_excluding( :no_ci ) if ENV['SEMAPHORE'] || ENV['CI']

	config.include( Loggability::SpecHelpers )
	config.include( Arborist::TestHelpers )
end


