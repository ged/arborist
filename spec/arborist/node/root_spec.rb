#!/usr/bin/env rspec -cfd

require_relative '../../spec_helper'

require 'arborist/node/root'


describe Arborist::Node::Root do

	it "is a singleton" do
		expect( described_class.new ).to be( described_class.new )
	end

end

