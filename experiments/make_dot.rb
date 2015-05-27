#!/usr/bin/env ruby
#
# This script takes a built node tree from a manager instance, and
# builts a .dot file from it.
#
#	./make_dot.rb [path-to-node-files] | dot -Tpdf -o nodes.pdf
#

require 'arborist'

manager = Arborist.manager_for( ARGV.first )
$dot    =  "digraph nodes {\n"


# Global opts
#
attrs   = {
	concentrate: 'true',
	# size:        '8,10.5',
	# ratio:       'fill',
	# ranksep:  1,
	# rankdir:  'LR'
}
attrs.each_pair{|key, val| $dot << "\t#{key}=\"#{val}\";\n"}


# Initial labeling, type, look and feel
#
manager.nodelist.each do |n|
	node  = manager.nodes[ n ]
	attrs = {}

	attrs[ :fontname ]  = 'Helvetica'
	attrs[ :shape ]     = "box" unless node.is_a?( Arborist::Node::Service )
	attrs[ :label ]     = node.identifier.dup.sub( "#{node.parent}-", '' )
	attrs[ :label ] << "\\n#{node.description}" if node.description

	if node.identifier == "_"
		attrs[ :label ] = "Arborist"
		attrs[ :style ] = "bold"
		attrs[ :shape ] = "polygon"
		attrs[ :skew ]  = 0.4
	end

	opts = attrs.each_with_object( [] ) {|(key, val), acc| acc << "#{key}=\"#{val}\"" }.join( ' ' )
	$dot << "\t\"#{n}\" [#{opts}];\n"
end


# Now just walk the tree, creating the relational hookups.
#
manager.all_nodes do |node|
	next if node.identifier == "_"
	$dot << "\t\"%s\" -> \"%s\";\n" % [ node.parent || "_", node.identifier ]
end

$dot << "}\n"
puts $dot

