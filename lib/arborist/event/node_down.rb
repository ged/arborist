# -*- ruby -*-
#encoding: utf-8

require 'arborist/event' unless defined?( Arborist::Event )
require 'arborist/event/node'


# An event generated when a node goes down.
class Arborist::Event::NodeDown < Arborist::Event::Node
end # class Arborist::Event::NodeDown
