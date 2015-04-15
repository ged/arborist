# -*- ruby -*-
#encoding: utf-8

require 'pathname'
require 'loggability'

require 'arborist' unless defined?( Arborist )
require 'arborist/node'
require 'arborist/mixins'


# The main Arborist process -- responsible for coordinating all other activity.
class Arborist::Manager
	extend Loggability,
	    Arborist::MethodUtilities


	##
	# Use the Arborist logger
	log_to :arborist


	#
	# Instance methods
	#

	### Create a new Arborist::Manager.
	def initialize
		@root = Arborist::Node.create( :root )
		@nodes = {
			'_' => @root,
		}
		@tree_built = false
	end


	######
	public
	######

	##
	# The root node of the tree.
	attr_accessor :root

	##
	# The Hash of all loaded Nodes, keyed by their identifier
	attr_accessor :nodes


	##
	# Flag for marking when the tree is built successfully the first time
	attr_predicate_accessor :tree_built


	### Add nodes yielded from the specified +enumerator+ into the manager's
	### tree.
	def load_tree( enumerator )
		enumerator.each do |node|
			self.add_node( node )
		end
		self.build_tree
	end


	### Build the tree out of all the loaded nodes.
	def build_tree
		self.log.info "Building tree from %d loaded nodes." % [ self.nodes.length ]
		self.nodes.each do |identifier, node|
			next if node.operational?
			self.link_node_to_parent( node )
		end
		self.tree_built = true
	end


	### Link the specified +node+ to its parent. Raises an error if the specified +node+'s
	### parent is not yet loaded.
	def link_node_to_parent( node )
		parent_id = node.parent || '_'
		parent_node = self.nodes[ parent_id ] or
			raise "no parent '%s' node loaded for %p" % [ parent_id, node ]

		self.log.debug "adding %p as a child of %p" % [ node, parent_node ]
		parent_node.add_child( node )
	end


	### Add the specified +node+ to the Manager.
	def add_node( node )
		identifier = node.identifier

		self.remove_node( self.nodes[identifier] )
		self.nodes[ identifier ] = node

		self.log.debug "Linking node %p to its parent" % [ node ]
		self.link_node_to_parent( node ) if self.tree_built?
	end


	### Remove a +node+ from the Manager. The +node+ can either be the Arborist::Node to
	### remove, or the identifier of a node.
	def remove_node( node )
		node = self.nodes[ node ] unless node.is_a?( Arborist::Node )
		return unless node

		raise "Can't remove an operational node" if node.operational?

		self.log.info "Removing node %p" % [ node ]
		node.children.each do |identifier, child_node|
			self.remove_node( child_node )
		end

		if parent_node = self.nodes[ node.parent || '_' ]
			parent_node.remove_child( node )
		end

		return self.nodes.delete( node.identifier )
	end


	### Yield each node in a depth-first traversal of the manager's tree
	### to the specified +block+, or return an Enumerator if no block is given.
	def all_nodes( &block )
		iter = self.enumerator_for( self.root )
		return iter.each( &block ) if block
		return iter
	end


	### Yield each node that is not down to the specified +block+, or return
	### an Enumerator if no block is given.
	def reachable_nodes( &block )
		iter = self.enumerator_for( self.root ) {|node| !node.down? }
		return iter.each( &block ) if block
		return iter
	end


	#########
	protected
	#########

	### Return an enumerator for the specified +node+.
	def enumerator_for( start_node, &filter )
		return Enumerator.new do |yielder|
			traverse = ->( node ) do
				yielder.yield( node )
				node.each( &traverse ) if !filter || filter[ node ]
			end
			traverse.call( start_node )
		end
	end

end # class Arborist::Manager
