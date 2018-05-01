# -*- ruby -*-
#encoding: utf-8

require 'arborist'

Arborist::Host 'vhost01' do
	parent 'duir'
	description "Virtual Host server"
	address '192.168.16.75'

	tags :infrastructure

	depends_on 'sidonie-iscsi'
end


Arborist::Host 'sandbox01' do
	parent 'vhost01'
	description "Scratch copy-on-write server for experiments"

	service 'canary', port: 12131, protocol: 'udp'
end

