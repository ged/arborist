# -*- ruby -*-
#encoding: utf-8

require 'arborist/event' unless defined?( Arborist::Event )
require 'arborist/event/node'


# An event generated when a node is quieted by one of its dependencies going
# down.
class Arborist::Event::NodeQuieted < Arborist::Event::Node
end # class Arborist::Event::NodeQuieted
