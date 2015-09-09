# -*- ruby -*-
#encoding: utf-8

require 'arborist'


Arborist::Host 'sidonie' do
	parent 'duir'
	description "NAS and media server"
	address '192.168.16.3'

	tags :infrastructure,
	     :storage,
	     :media,
	     :rip_status_check

	service 'ssh'
	service 'demon-http', port: 6666, protocol: 'http'
	service 'postgresql'

	service 'smtp'

	service 'http'
	service 'sabnzbd', port: 8080, type: 'http'
	service 'sickbeard', port: 8081, type: 'http'
	service 'pms', port: 32400, type: 'http'
	service 'couchpotato', port: 5050, type: 'http'

end
