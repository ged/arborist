#!/usr/bin/env ruby
#encoding: utf-8
# vim: set noet nosta sw=4 ts=4 :
#
#
# Test script to build an Arborist node tree from an existing LDAP
# host/service structure.

require 'pathname'
$LOAD_PATH.unshift( Pathname(__FILE__).dirname.parent + 'lib' )

require 'arborist'
require 'treequel'
require 'pry'

DIRECTORY = Treequel.directory( 'ldaps://ldap-staging.laika.com/dc=laika,dc=com' )
Arborist.load_config

def dn_to_fqdn( dn )
	return dn.split( /\s*,\s*/ ).
		reject  {|part| part !~ /^(cn|dc)=/ }.
		collect {|part| part.sub(/^\w+=/, '') }.
		join( '-' )
end

GATEWAY_MAP = DIRECTORY.
	filter( :objectClass => 'ArboristNode', :ipGatewayNumber => '*' ).
	each_with_object( {} ) do |entry, acc|
		hostobj = DIRECTORY.filter( :ipHostNumber => entry[:ipGatewayNumber] ).first or next
		acc[ entry.dn ] = hostobj.dn
	end


def find_parent( entry )
	parent = entry.parent or return
	return parent if parent[:objectClass].include?( 'ArboristNode' )
	return find_parent( parent )
end


nodeiter = Enumerator.new do |yielder|
	DIRECTORY.filter( :and, [:objectClass, 'ArboristNode'], [:objectClass => 'iphost'] ).each do |entry|
		identifier = dn_to_fqdn( entry.dn )
		node = Arborist::Node.create( 'host', identifier )

		puts "Working on %s" % [ entry.dn ]

		unless GATEWAY_MAP.value?( entry.dn )
			node_parent = find_parent( entry ) or next
			parent_dn = if node_parent[:objectClass].include?('dcObject')
							GATEWAY_MAP[ node_parent.dn ]
						else
							node_parent.dn
						end

			node.parent( dn_to_fqdn(parent_dn) )
		end

		node.description( entry[:description].first )
		yielder.yield( node )

		DIRECTORY.from( entry ).filter( :objectClass => 'ipService' ).scope( :one ).each do |service|
			port    = service[ :ipServicePort ]
			proto   = service[ :ipServiceProtocol ]
			puts " --- Working on %s" % [ service.dn ]
			servicenode = Arborist::Node.create( 'service', service[:cn].first, node, :port => port, :protocol => proto )
			servicenode.description( service[:description].first )
			yielder.yield( servicenode )
		end
	end
end

manager = Arborist::Manager.new
manager.load_tree( nodeiter )
manager.build_tree

# manager.run

require 'pry'
binding.pry

