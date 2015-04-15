# -*- ruby -*-
#encoding: utf-8

require 'arborist/node' unless defined?( Arborist::Node )


# The class of the root node of an Arborist tree. This class is a Singleton.
class Arborist::Node::Root < Arborist::Node

	# The instance of the Root node.
	@instance = nil


	### Create the instance of the Root node (if necessary) and return it.
	def self::new( * )
		@instance ||= super
		return @instance
	end


	### Reset the singleton instance; mainly used for testing.
	def self::reset
		@instance = nil
	end


	### Set up the root node.
	def initialize( * )
		super( '_' ) do
			description "The root node."
			source = URI( __FILE__ )
		end
	end

end # class Arborist::Node::Root
