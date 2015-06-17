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
	service 'rabbitmq', app_protocol: 'amqp'
	service 'postgresql'

	service 'cozy_frontend',       port: 3000, app_protocol: 'http'
	service 'cozy_admin_frontend', port: 4331, app_protocol: 'http'
	service 'cozy_services',       port: 8888, app_protocol: 'http'
	service 'cozy_admin_services', port: 8889, app_protocol: 'http'

end

