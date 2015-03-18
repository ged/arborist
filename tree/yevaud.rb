# -*- ruby -*-
#encoding: utf-8

require 'arborist'


Arborist::Host 'yevaud' do
	parent 'duir'
	address 'yevaud.home'

	description "Latop, running services for development."

	tags :laptop,
	     :developer

	service 'ssh'
	service 'rabbitmq', port: 'amqp'
	service 'postgresql'

	webservice 'cozy_frontend',       port: 3000
	webservice 'cozy_admin_frontend', port: 4331
	webservice 'cozy_services',       port: 8888
	webservice 'cozy_admin_services', port: 8889

end

