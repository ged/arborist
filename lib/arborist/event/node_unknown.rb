# -*- ruby -*-
#encoding: utf-8

require 'arborist/event' unless defined?( Arborist::Event )
require 'arborist/event/node'


# An event generated when a node transitions to an unknown state.
class Arborist::Event::NodeUnknown < Arborist::Event::Node
end # class Arborist::Event::NodeUnknown
