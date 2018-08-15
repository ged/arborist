# -*- ruby -*-
#encoding: utf-8

require 'pp'
require 'json'
require 'yaml'
require 'msgpack'
require 'tty-tree'

require 'arborist/cli' unless defined?( Arborist::CLI )
require 'arborist/client'


# Command to dump the node tree of a running Arborist manager
module Arborist::CLI::Tree
	extend Arborist::CLI::Subcommand

	desc 'Dump the node tree of the running manager'

	command :tree do |cmd|
		cmd.switch :raw,
			desc: "Dump the node tree data as raw data instead of prettifying it.",
			negatable: false
		cmd.switch :path,
			desc: "Include the parent path back to root, when using --from.",
			negatable: false

		cmd.flag :format,
			desc: "When dumping the tree using --raw, serialize to this format.",
			must_match: %w[ yaml json ]
		cmd.flag [:f, :from],
			type: String,
			desc: "Start at a node other than the root.",
			arg_name: 'identifier'
		cmd.flag [:e, :depth],
			type: Integer,
			desc: "Limit the depth of the fetched tree.",
			arg_name: 'integer'

		cmd.action do |globals, options, args|
			client = Arborist::Client.instance

			opts = { tree: true }
			opts[ :from ]  = options[ :from ]  if options[ :from ]
			opts[ :depth ] = options[ :depth ] if options[ :depth ]

			nodes = client.fetch( opts )

			if options[:raw]
				case options[:format]
				when 'json'
					puts JSON.dump( nodes.first )
				when 'yaml'
					puts YAML.dump( nodes.first )
				else
					pp nodes.first
				end

			else
				status = client.status
				prompt.say "Arborist Manager %s {%s} [%s nodes] (uptime: %s secs)\n\n" % [
					highlight_string( status['server_version'] ),
					highlight_string( client.tree_api_url ),
					highlight_string( status['nodecount'] ),
					highlight_string( "%d" % status['uptime'] )
				]

				root = nodes.first
				root_data = {}

				# Recursively fetch each parent node upwards to the
				# Arborist root.
				#
				tree_data = if options[ :path ] && options[ :from ]
					path_to_root = fetch_parents( root )
					{ node_description( path_to_root.shift ) => build_path( path_to_root, root ) }

				# Just display starting at the specified root.
				#
				else
					{ node_description(root) => root_data }
				end

				root[ 'children' ].each_value do |node|
					root_data[ node_description(node) ] = build_tree( node )
				end

				tree = TTY::Tree.new( tree_data )
				prompt.say tree.render( indent: 4 )
			end
		end

	end


	###############
	module_function
	###############

	#### Reorganize the node data to format used by TTY::Tree.
	def build_tree( node )
		return [] if node[ 'children' ].empty?

		children = []
		node[ 'children' ].each_value do |child|
			children << { node_description(child) => build_tree(child) }
		end
		return children
	end


	### Given a sorted array of +nodes+, reorganize it for TTY::Tree.
	def build_path( nodes, root )
		children = []
		parent_node = nodes.shift
		return children unless parent_node

		if parent_node == root
			children << { node_description(parent_node) => build_tree(parent_node) }
		else
			children << { node_description(parent_node) => build_path(nodes, root) }
		end
		return children
	end


	### Given a starting node, walk upwards through the tree until
	### reaching the Arborist root node.  Returns an array of nodes,
	### sorted root down.
	def fetch_parents( start_node )
		client = Arborist::Client.instance
		path = [ start_node ]
		parent = start_node[ 'parent' ]
		while parent
			parent_node = client.fetch_node( parent )
			path << parent_node
			parent = parent_node[ 'parent' ]
		end
		return path.reverse
	end


	### Return a description of the specified +node+.
	def node_description( node )
		desc = ""

		case node['type']
		when 'root'
			desc << "%s" % [ hl.bold.bright_blue(node['type']) ]
		else
			desc << highlight_string( node['identifier'] )
			desc << " %s" % [ hl.dark.white(node['type']) ]
		end

		desc << " [%s]" % [ node['description'] ] unless
			!node['description'] || node['description'].empty?
		desc << " (%s)" % [ status_description(node) ]

		child_count = node[ 'children' ].length
		desc << " [%d child node%s" % [
			child_count, child_count == 1 ? ']' : 's]'
		] unless child_count.zero?

		case node['status']
		when 'down'
			desc << errors_description( node )
		when 'warn'
			desc << warnings_description( node )
		when 'quieted'
			desc << quieted_reasons_description( node )
		when 'acked'
			desc << ack_description( node )
			desc << "; was: "
			desc << errors_description( node )
		end

		return desc
	end


	### Return a more colorful description of the status of the given +node+.
	def status_description( node )
		status = node['status'] or return '-'
		return hl.decorate( status, status.to_sym ) rescue status
	end


	### Return the errors from the specified +node+ in a single line.
	def errors_description( node )
		errors = node['errors'] or return ''
		return '  ' + errors.map do |monid, error|
			"%s: %s" % [ monid, error ]
		end.join( '; ' )
	end

	### Return the warnings from the specified +node+ in a single line.
	def warnings_description( node )
		warnings = node['warnings'] or return ''
		return '  ' + warnings.map do |monid, error|
			"%s: %s" % [ monid, error ]
		end.join( '; ' )
	end


	### Return the quieted reasons from the specified +node+ in a single line.
	def quieted_reasons_description( node )
		reasons = node['quieted_reasons'] or return ''
		return '  ' + reasons.map do |depname, reason|
			"%s: %s" % [ depname, reason ]
		end.join( '; ' )
	end


	### Return a description of the acknowledgement from the node.
	def ack_description( node )
		ack = node['ack'] or return '(no ack)'

		return " Acked by %s at %s%s: %s" % [
			ack['sender'],
			ack['time'],
			ack['via'] ? ' via ' + ack['via'] : '',
			ack['message']
		]
	end

end # module Arborist::CLI::Tree

