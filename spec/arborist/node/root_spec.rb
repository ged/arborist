#!/usr/bin/env rspec -cfd

require_relative '../../spec_helper'

require 'arborist/node/root'


describe Arborist::Node::Root do

	let( :node ) { described_class.instance }


	it "is a singleton" do
		expect( described_class.new ).to be( described_class.new )
	end


	it "doesn't have a parent node" do
		expect( node.parent ).to be_nil
	end


	it "doesn't allow a parent to be set on it" do
		node.parent( 'supernode' )
		expect( node.parent ).to be_nil
	end


	it "immediately transitions to up when re-enabled" do
		expect( node ).to be_up

		node.acknowledge(
			message: 'METEOR COMING DISABLE ALERTS THAT WILL BE 100K KPLZTHX',
			sender:  'SunGuard'
		)
		expect( node ).to be_disabled

		node.unacknowledge
		expect( node ).to be_up
	end
end

