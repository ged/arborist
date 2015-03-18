#!/usr/bin/env rspec -cfd

require_relative '../spec_helper'

require 'arborist/collector'


describe Arborist::Collector do

	it "starts with a graph of itself and its host" do
		expect( described_class.new.dag.size ).to eq( 2 )
	end

end

