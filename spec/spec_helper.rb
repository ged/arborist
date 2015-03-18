# -*- ruby -*-
#encoding: utf-8

require 'bundler/setup'

require 'simplecov' if ENV['COVERAGE']
require 'rspec'
require 'loggability/spechelpers'


RSpec.configure do |config|
	config.run_all_when_everything_filtered = true
	config.filter_run :focus
	config.order = 'random'
	config.mock_with( :rspec ) do |mock|
		mock.syntax = :expect
	end

	config.include( Loggability::SpecHelpers )
end


