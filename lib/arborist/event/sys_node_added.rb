# -*- ruby -*-
#encoding: utf-8

require 'arborist/event' unless defined?( Arborist::Event )
require 'arborist/event/node'


# A system event generated when a node is added to the tree.
class Arborist::Event::SysNodeAdded < Arborist::Event::Node
end # class Arborist::Event::SysNodeAdded
