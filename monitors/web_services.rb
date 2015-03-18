# -*- ruby -*-
#encoding: utf-8

require 'net/http'
require 'arborist/monitor'

Arborist::Monitor 'web service check'
	match type: 'webservice'
	run do |node|
		Net::HTTP
	end
end
