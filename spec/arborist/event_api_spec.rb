#!/usr/bin/env rspec -cfd

require_relative '../spec_helper'

require 'arborist/event_api'


describe Arborist::EventAPI do

	let( :uuid ) { '9E630B46-B0D2-4658-AFE6-ED4A1E838C69' }

	it "encodes events published by the Manager" do
		encoded = described_class.encode( uuid, {a: 1, b: 2} )
		expect( encoded ).to be_a( CZTop::Message )
		identifier, payload = described_class.decode( encoded )
		expect( identifier ).to eq( uuid )
		expect( payload ).to eq({ 'a' => 1, 'b' => 2 })
	end


end


