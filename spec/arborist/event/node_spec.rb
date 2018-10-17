#!/usr/bin/env rspec -cfd

require_relative '../../spec_helper'

require 'arborist/node'
require 'arborist/subscription'
require 'arborist/event/node'


describe Arborist::Event::Node do

	let( :node ) do
		TestNode.new( 'foo' ) do
			parent 'bar'
			description "A testing node"
			tags :yelp, :yank, :yore, :yandex

			update(
				"tcp_socket_connect" => {
					"time" => "2016-02-25 16:04:35 -0800",
					"duration" => 0.020619
				}
			)
		end
	end
	let( :event ) { described_class.new(node) }


	it "serializes with useful metadata attached" do
		expect( event.to_h ).to include( :identifier, :parent, :nodetype, :flapping )
		expect( event.to_h[:nodetype] ).to eq( 'testnode' )
		expect( event.to_h[:parent] ).to eq( 'bar' )
		expect( event.to_h[:flapping] ).to eq( false )
	end


	it "matches match-anything subscriptions" do
		sub = Arborist::Subscription.new {}
		expect( event ).to match( sub )
	end


	it "matches subscriptions which have matching criteria" do
		criteria = {
			tag: node.tags.last,
			status: node.status
		}
		sub = Arborist::Subscription.new( nil, criteria ) {}

		expect( event ).to match( sub )
	end


	it "matches subscriptions which have non-matching negative criteria" do
		negative_criteria = {
			tag: 'nope'
		}
		sub = Arborist::Subscription.new( nil, {}, negative_criteria ) {}

		expect( event ).to match( sub )
	end


end

