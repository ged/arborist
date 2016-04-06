# -*- ruby -*-
#encoding: utf-8

require 'arborist/event' unless defined?( Arborist::Event )
require 'arborist/event/node'


# An event generated when a node comes up.
class Arborist::Event::NodeUp < Arborist::Event::Node
end # class Arborist::Event::NodeUp
