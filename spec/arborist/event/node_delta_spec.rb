#!/usr/bin/env rspec -cfd

require_relative '../../spec_helper'

require 'arborist/event/node_delta'


describe Arborist::Event::NodeDelta do

	class TestNode < Arborist::Node; end


	let( :node ) do
		TestNode.new( 'foo' ) do
			parent 'bar'
			description "A testing node"
			tags :tree, :try, :triage, :trip

			update(
				"tcp_socket_connect" => {
					"time" => "2016-02-25 16:04:35 -0800",
					"duration" => 0.020619
				}
			)
		end
	end


	describe "subscription support" do

		it "matches a subscription with only an event type if the type is the same" do
			sub = Arborist::Subscription.new( 'node.delta' ) {}
			event = described_class.new( node, status: ['up', 'down'] )

			expect( event ).to match( sub )
		end


		it "matches a subscription with a matching event type and matching criteria" do
			sub = Arborist::Subscription.new( 'node.delta', 'tag' => 'triage' ) {}
			event = described_class.new( node, status: ['up', 'down'] )

			expect( event ).to match( sub )
		end


		it "matches a subscription with matching event type, node criteria, and delta criteria" do
			criteria = {
				'tag' => 'tree',
				'delta' => {
					'status' => [ 'up', 'down' ]
				}
			}

			sub = Arborist::Subscription.new( 'node.delta', criteria ) {}
			event = described_class.new( node, 'status' => ['up', 'down'] )

			expect( event ).to match( sub )
		end


		it "doesn't match a subscription with matching negative criteria" do
			sub = Arborist::Subscription.new( 'node.delta', 'type' => node.type ) {}
			sub.exclude( 'delta' => {status: ['up', 'down']} )
			event = described_class.new( node, 'status' => ['up', 'down'] )

			expect( event ).to_not match( sub )
		end

	end


end

