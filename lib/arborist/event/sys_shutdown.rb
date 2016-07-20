# -*- ruby -*-
#encoding: utf-8

require 'arborist/event' unless defined?( Arborist::Event )
require 'arborist/event/node'


# A system event generated when the manager starts shutting down.
class Arborist::Event::SysShutdown < Arborist::Event
end # class Arborist::Event::SysShutdown
