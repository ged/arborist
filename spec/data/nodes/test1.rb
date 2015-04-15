# -*- ruby -*-
#encoding: utf-8

require 'arborist'

Arborist::Host 'duir' do
	description "Router box"
	address '192.168.16.1'

	tags :infrastructure
end

