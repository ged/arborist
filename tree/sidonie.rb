# -*- ruby -*-
#encoding: utf-8

require 'arborist'


Arborist::Host 'sidonie' do
	parent 'duir'
	address '192.168.16.3'

	description "Media server, NAS."

	tags :storage,
	     :media,
		 :rip_status_check

	service 'ssh'
	service 'http', port: 6666
	service 'postgresql'

	service 'smtp'

	webservice
	webservice 'sabnzbd', port: 8080
	webservice 'sickbeard', port: 8081
	webservice 'plex media server', ports: [32400, 32401]
	webservice 'couch potato', port: 5050

end
