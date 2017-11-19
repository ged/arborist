# -*- ruby -*-
#encoding: utf-8

require 'pp'
require 'msgpack'

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

		cmd.flag [:f, :from],
			type: String,
			desc: "Start at a node other than the root.",
			arg_name: 'identifier'
		cmd.flag [:e, :depth],
			type: Integer,
			desc: "Limit the depth of the fetched tree.",
			arg_name: 'integer'

		cmd.action do |globals, options, args|
			client = Arborist::Client.new

			opts = { tree: true }
			opts[:from] = options[:from] if options[:from]
			opts[:depth] = options[:depth] if options[:depth]

			status = client.status
			nodes = client.fetch( opts )
			root = nodes.first

			prompt.say "Arborist Manager %s {%s} [%s nodes] (uptime: %ss)" % [
				highlight_string(status['server_version']),
				highlight_string(client.tree_api_url),
				highlight_string(status['nodecount']),
				highlight_string(status['uptime'])
			]

			if options[:raw]
				pp root
			else
				dump_tree( root, options )
			end
		end

	end


	###############
	module_function
	###############

	### Dump the node tree starting at the specified +root+ node.
	def dump_tree( node, options )
		desc = node_description( node, options )
		prompt.say( desc )

		prompt.indent do
			node['children'].each_value do |subnode|
				dump_tree( subnode, options )
			end
		end
	end


	### Return a description of the specified +node+.
	def node_description( node, options )
		desc = highlight_string( node['identifier'] )
		desc << " %s" % [ hl(node['type']).color( :dark, :white ) ]
		desc << " [%s]" % [ node['description'] ] unless
			!node['description'] || node['description'].empty?
		desc << " (%s)" % [ status_description(node) ]

		child_count = node[ 'children' ].length
		desc << " [%d child nodes]" % [ child_count ] unless child_count.zero?

		case node['status']
		when 'down'
			desc << errors_description( node )
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
		return hl( status ).color( status.to_sym ) rescue status
	end


	### Return the errors from the specified +node+ in a single line.
	def errors_description( node )
		errors = node['errors'] or return ''
		return '  ' + errors.map do |monid, error|
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

