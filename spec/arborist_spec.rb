#!/usr/bin/env rspec -cfd

require_relative 'spec_helper'

require 'arborist'


describe Arborist do

	it "has a semantic version" do
		expect( described_class::VERSION ).to match( /^\d+\.\d+\.\d+/ )
	end

end

