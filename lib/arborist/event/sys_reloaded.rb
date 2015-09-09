#!/usr/bin/env ruby

require 'arborist/node' unless defined?( Arborist::Node )


# An event sent when the manager reloads the node tree.
class Arborist::Event::SysReloaded < Arborist::Event


	### Create a NodeUpdate event for the specified +node+.
	def initialize( payload=Time.now )
		super
	end

end # class Arborist::Event::NodeUpdate
