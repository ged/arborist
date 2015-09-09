# -*- ruby -*-
#encoding: utf-8

require 'arborist'


Arborist::Observer do
	subscribe to: 'node.delta', where: { status: ['up', 'down'] }

	action

end