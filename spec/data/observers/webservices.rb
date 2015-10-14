# -*- ruby -*-
#encoding: utf-8

require 'arborist'


Arborist::Observer "Webservers" do
	subscribe to: 'node.delta',
		where: { type: 'service', port: [80, 443], status: ['up', 'down'] }

	action do |uuid, event|
		title = "Webserver %s is DOWN (%s)" % [ event['identifier'], Time.now ]
		message = event.to_s

		Pushover.notification( message, title, user: USER_TOKEN, token: APP_TOKEN)
	end

end

