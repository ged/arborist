# -*- ruby -*-
#encoding: utf-8

require 'arborist'


Arborist::Observer "Audit Logger" do
	subscribe to: 'node.update', on: 'localhost'
	action do |event|
		$stderr.puts "%p" % [ event ]
	end
	summarize( every: 8 ) do |events|
		$stderr.puts "Audit summary:"
		events.each do |time, ev|
			$stderr.puts "  [%s] %s: %p" % [
				time.strftime('%Y-%m-%d %H:%M:%S %z'),
				ev['type'],
				ev['data']
			]
		end
	end
end

