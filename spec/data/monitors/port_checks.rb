# -*- ruby -*-
#encoding: utf-8

require 'arborist/monitor'
require 'arborist/monitor/socket'

using Arborist::TimeRefinements

Arborist::Monitor 'port checks on all tcp services' do
	every 5.seconds
	match type: 'service', protocol: 'tcp'
	use :addresses, :port
	exec( Arborist::Monitor::Socket::TCP )
end

Arborist::Monitor 'port checks on downed tcp services' do
	every 10.seconds
	match type: 'service', protocol: 'tcp', status: 'down'
	include_down true
	use :addresses, :port
	exec( Arborist::Monitor::Socket::TCP )
end


