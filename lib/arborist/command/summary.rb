# -*- ruby -*-
#encoding: utf-8

require 'time'

require 'arborist/cli' unless defined?( Arborist::CLI )
require 'arborist/client'


# Command to fetch down/acked/disabled nodes for quick display.
module Arborist::CLI::Summary
	extend Arborist::CLI::Subcommand
	using Arborist::TimeRefinements

	BANNER = [
		'          _             _    _',
		' __ _ _ _| |__  ___ _ _(_)__| |',
		'/ _` | \'_| \'_ \\/ _ \\ \'_| (_-< _|',
		'\\__,_|_| |_.__/\\___/_| |_/__/\\__| %s, %s nodes',
	]

	desc 'Summarize known problems'

	command :summary do |cmd|

		cmd.flag [:s, :sort],
			type: String,
			desc: "Sort output by this node key",
			arg_name: 'sort',
			default_value: 'status_changed'

		cmd.action do |globals, options, args|
			client = Arborist::Client.new
			status = client.status
			nodes  = client.fetch

			down     = get_status( nodes, 'down' )
			acked    = get_status( nodes, 'acked' )
			disabled = get_status( nodes, 'disabled' )
			quieted  = get_status( nodes, 'quieted' )
			problems = ! ( down.size + acked.size + disabled.size ).zero?

			prompt.say "Connected to: %s" % [ highlight_string(client.tree_api_url) ]
			prompt.say "Status as of: %s" % [ hl.on_blue.bright_white(Time.now.to_s) ]

			(0..2).each do |i|
				prompt.say "%s" % [ hl.bold.bright_green( BANNER[i] ) ]
			end
			prompt.say hl.bold.bright_green( BANNER.last ) % [
				highlight_string(status['server_version']),
				highlight_string(status['nodecount'])
			]

			puts
			if problems
				output_problems( disabled, acked, down, quieted, options[:sort] )
			else
				prompt.say success_string( "No problems found!" )
			end
		end

	end


	###############
	module_function
	###############

	### Since we fetch all nodes instead of doing separate
	### API searches, quickly return nodes of a given +status+.
	def get_status( nodes, status )
		return nodes.select{|n| n['status'] == status}
	end


	### Output all problems.
	###
	def output_problems( disabled, acked, down, quieted, sort )
		unless disabled.size.zero?
			prompt.say hl.headline( "Disabled Nodes" )
			display_table( *format_acked(disabled, sort) )
			puts
		end
		unless acked.size.zero?
			prompt.say hl.headline( "Acknowledged Outages" )
			display_table( *format_acked(acked, sort) )
			puts
		end
		unless down.size.zero?
			prompt.say hl.headline( "Current Outages" )
			header = [
				highlight_string( 'identifier' ),
				highlight_string( 'type' ),
				highlight_string( 'when' ),
				highlight_string( 'errors' )
			]

			display_table( header, format_down(down, sort) )
			prompt.say "%d nodes have been %s as a result of the above problems." % [
				quieted.size,
				hl.quieted( 'quieted' )
			]
			puts
		end
	end


	### Prepare an array of acked/disabled nodes.
	def format_acked( nodes, sort_key )
		header = [
			highlight_string( 'identifier' ),
			highlight_string( 'type' ),
			highlight_string( 'when' ),
			highlight_string( 'who' ),
			highlight_string( 'message' )
		]

		rows = nodes.sort_by{|n| n[sort_key] }.each_with_object([]) do |node, acc|
			acc << [
				hl.disabled( node['identifier'] ),
				node[ 'type' ],
				Time.parse( node[ 'status_changed' ] ).as_delta,
				node[ 'ack' ][ 'sender' ],
				node[ 'ack' ][ 'message' ]
			]
		end
		return header, rows
	end


	### Prepare an array of down nodes.
	def format_down( nodes, sort_key )
		return nodes.sort_by{|n| n[sort_key] }.each_with_object([]) do |node, acc|
			errors = node[ 'errors' ].map{|err| "%s: %s" % [ err.first, err.last ]}
			acc << [
				hl.down( node['identifier'] ),
				node[ 'type' ],
				Time.parse( node[ 'status_changed' ] ).as_delta,
				errors.join( '\n' )
			]
		end
	end

end # module Arborist::CLI::Summary

