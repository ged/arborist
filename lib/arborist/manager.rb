# -*- ruby -*-
#encoding: utf-8

require 'pathname'
require 'loggability'
require 'rgl/adjacency'
require 'rgl/traversal'

require 'arborist' unless defined?( Arborist )
require 'arborist/node'
require 'arborist/mixins'


# The main Arborist process -- responsible for coordinating all other activity.
class Arborist::Manager
	extend Loggability,
	       Configurability,
	       Arborist::MethodUtilities


	# Configurability API -- reasonable default config values
	DEFAULT_CONFIG = {
		tree_dir: './tree'
	}


	##
	# Use the Arborist logger
	log_to :arborist

	##
	# Use the 'manager' section of the config
	config_key :manager


	##
	# The Pathname of the directory to search for the files describing the monitoring tree
	singleton_attr_accessor :tree_dir


	### Configurability API -- configure the Manager with the specified +config+. If the
	### +config+ is +nil+, use the default config.
	def self::configure( config=nil )
		config = self.defaults.merge( config || {} )

		self.tree_dir = Pathname( config[:tree_dir] )
	end


	#
	# Instance methods
	#

	### Create a new Arborist::Manager.
	def initialize
		@graph = RGL::DirectedAdjacencyGraph[ '_', '_manager' ]
		@nodes = {
			'_'        => Arborist::Node.create( :root ),
			'_manager' => self,
		}
	end


	######
	public
	######

	##
	# The adjacency graph that's used to represent the tree of monitored systems.
	attr_accessor :graph

	##
	# The Hash of all loaded Nodes, keyed by their identifier
	attr_accessor :nodes


	### Add nodes yielded from the specified +enumerator+ into the manager's
	### graph.
	def load_graph( enumerator )
		enumerator.each do |node|
			self.add_node( node )
		end
	end


	### Add the specified +node+ to the Manager's graph.
	def add_node( node )
		identifier = node.identifier
		parent = node.parent || '_'

		if (( old_node = self.nodes[identifier] ))
			unless old_node.source == node.source
				self.log.warn "Replacing %p with %p" % [ old_node, node ]
			end
		end

		self.nodes[ identifier ] = node
		self.graph.add_edge( parent, identifier )

		node.subnodes.each do |subnode|
			self.add_node( subnode )
		end
	end


	class NodeDumper < RGL::DFSVisitor

		def examine_vertex( u, v )
			super
			pp([ u, v ])
		end

	end


end # class Arborist::Manager
