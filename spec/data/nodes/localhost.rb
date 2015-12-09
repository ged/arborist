# -*- ruby -*-
#encoding: utf-8

require 'arborist'

Arborist::Host 'localhost' do
	description "The local machine"
	address '127.0.0.1'

	tags :testing

	service 'testing', port: 10000

end

