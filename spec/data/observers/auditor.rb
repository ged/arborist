# -*- ruby -*-
#encoding: utf-8

require 'arborist'


Arborist::Observer "Audit Logger" do
	subscribe to: 'node.update', on: 'localhost'
	action do |uuid, event|
		$stderr.puts "%s: %p" % [ uuid, event ]
	end
end

