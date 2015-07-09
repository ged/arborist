# -*- ruby -*-
#encoding: utf-8

require 'arborist/monitor'
require 'arborist/mixins'

using Arborist::TimeRefinements

Arborist::Monitor 'disk space' do
	match type: 'host'
	every 5.minutes
	exec ''
end

Arborist::Monitor 'media server disk space' do
	# hostgroup :bennett
	match type: 'host', tag: 'ldap'
	exclude tag: 'infrastructure'
	exclude type: 'host', name: ['havnor', 'torheven']
	exec 'fping'
end

Arborist::Monitor "down check" do
	match down: true
	exec do |nodes|
		nodes.map {|n| event :down_still, n.identifier }
	end
end


