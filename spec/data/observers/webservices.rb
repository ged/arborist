# -*- ruby -*-
#encoding: utf-8

require 'arborist'


Arborist::Observer "Webservers" do
	subscribe to: 'node.delta',
		where: {
			type: 'service',
			port: 80,
			delta: { status: ['up', 'down'] }
		}
	subscribe to: 'node.delta',
		where: {
			type: 'service',
			port: 443,
			delta: { status: ['up', 'down'] }
		}

	action do |uuid, event|
		$stderr.puts "Webserver %s is DOWN (%p)" % [ event['data']['identifier'], event['data'] ]
	end

end

