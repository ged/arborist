#!/usr/bin/env ruby

require 'set'

class Node
	def initialize( identifier )
		@identifier = identifier
	end

	attr_reader :identifier

	def eql?( other )
		p "eql?"
		return false unless other.is_a?( self.class )
		return other.identifier == self.identifier
	end

	def hash
		return @identifier.hash
	end
end


s = Set.new

node1 = Node.new( 'node1' )
node2 = Node.new( 'node2' )
node3 = Node.new( 'node3' )

node1_1 = Node.new( 'node1' )

#s.merge( node1, node2, node3 )

require 'pry'; binding.pry
1

#p s.add( node1_1 )

