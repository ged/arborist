#!/usr/bin/env ruby
#
# This script asks a running Arborist manager for a list of its
# known nodes, and builds a .dot file from it.
#
#	./make_dot.rb | dot -Tpdf -o nodes.pdf
#

require 'arborist'
require 'arborist/client'

Arborist.load_config

client  = Arborist::Client.new
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

nodes = client.list

# Initial labeling, type, look and feel
#
nodes.each do |node|
	attrs = {}

	attrs[ :fontname ]  = 'Helvetica'
	attrs[ :shape ]     = "box" unless node[ 'type' ] == 'service'
	attrs[ :label ]     = node['identifier'].sub( "#{node['parent']}-", '' )
	attrs[ :label ] << "\\n#{node['description']}" if node['description']

	if node[ 'identifier' ] == "_"
		attrs[ :label ] = "Arborist"
		attrs[ :style ] = "bold"
		attrs[ :shape ] = "polygon"
		attrs[ :skew ]  = 0.4
	end

	opts = attrs.each_with_object( [] ) {|(key, val), acc| acc << "#{key}=\"#{val}\"" }.join( ' ' )
	$dot << "\t\"#{node['identifier']}\" [#{opts}];\n"
end


# Now just walk the tree, creating the relational hookups.
#
nodes.each do |node|
	next if node[ 'identifier' ] == "_"
	$dot << "\t\"%s\" -> \"%s\";\n" % [ node['parent'] || "_", node['identifier'] ]
end

$dot << "}\n"
puts $dot

