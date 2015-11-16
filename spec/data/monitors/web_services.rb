# -*- ruby -*-
#encoding: utf-8

require 'net/http'
require 'arborist/monitor'
require 'arborist/mixins'

using Arborist::TimeRefinements

Arborist::Monitor 'web service check' do
	match type: 'webservice'
	exec do |nodes|
		Net::HTTP
	end
end


