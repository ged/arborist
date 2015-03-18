# -*- ruby -*-
#encoding: utf-8

require 'arborist/monitor'

Arborist::Monitor 'ping check' do
	every 2.seconds
	match type: 'host'
	exclude tag: :laptop
	use :address
	run 'fping'
end

Arborist::Monitor 'transient host pings' do
	match type: 'host', tag: 'laptop'
	run 'fping'

	every 5.minutes
end

