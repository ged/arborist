# -*- ruby -*-
#encoding: utf-8

require 'arborist'


Arborist::Host 'yevaud' do
	parent 'duir'
	address '192.168.16.10'

	description "Laptop, running services for development."

	tags :laptop,
	     :developer

	service 'ssh'
	service 'rabbitmq', port: 'amqp'
	service 'postgresql'

	service 'cozy_frontend',       port: 3000, type: 'http'
	service 'cozy_admin_frontend', port: 4331, type: 'http'
	service 'cozy_services',       port: 8888, type: 'http'
	service 'cozy_admin_services', port: 8889, type: 'http'

end

