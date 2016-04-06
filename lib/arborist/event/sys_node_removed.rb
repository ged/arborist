# -*- ruby -*-
#encoding: utf-8

require 'arborist/event' unless defined?( Arborist::Event )
require 'arborist/event/node'


# A system event generated when a node is removed from the tree.
class Arborist::Event::SysNodeRemoved < Arborist::Event::Node
end # class Arborist::Event::SysNodeRemoved
