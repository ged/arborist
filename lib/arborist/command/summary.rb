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
		'\\__,_|_| |_.__/\\___/_| |_/__/\\__| v%s, %s nodes',
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
			problems = ! ( down.size + acked.size + disabled.size ).zero?

			prompt.say "Connected to: %s" % [ highlight_string(client.tree_api_url) ]
			(0..2).each do |i|
				prompt.say "%s" % [ hl( BANNER[i] ).color( :success ) ]
			end
			prompt.say hl(BANNER.last).color( :success ) % [
				highlight_string(status['server_version']),
				highlight_string(status['nodecount'])
			]

			puts
			if problems
				unless disabled.size.zero?
					section "Disabled"
					display_table( format_acked(disabled, options[:sort]) )
					puts
				end
				unless acked.size.zero?
					section "Acknowledged"
					display_table( format_acked(acked, options[:sort]) )
					puts
				end
				unless down.size.zero?
					section "Down"
					display_table( format_down(down, options[:sort]) )
					puts
				end
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


	### Spit out a separator with a headline.
	def section( str )
		width = HighLine::SystemExtensions.terminal_size.first
		width = width > 72 ? 72 : width
		prompt.say "\n%s\n%s" % [ headline_string( str ), '-' * width ]
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
				hl( node['identifier'] ).color( :disabled ),
				node[ 'type' ],
				Time.parse( node[ 'status_changed' ] ).as_delta,
				node[ 'ack' ][ 'sender' ],
				node[ 'ack' ][ 'message' ]
			]
		end

		return rows.unshift( header )
	end


	### Prepare an array of down nodes.
	def format_down( nodes, sort_key )
		header = [
			highlight_string( 'identifier' ),
			highlight_string( 'type' ),
			highlight_string( 'when' ),
			highlight_string( 'errors' )
		]

		rows = nodes.sort_by{|n| n[sort_key] }.each_with_object([]) do |node, acc|
			errors = node[ 'errors' ].map{|err| "%s: %s" % [ err.first, err.last ]}
			acc << [
				hl( node['identifier'] ).color( :down ),
				node[ 'type' ],
				Time.parse( node[ 'status_changed' ] ).as_delta,
				errors.join( ', ' )
			]
		end

		return rows.unshift( header )
	end

end # module Arborist::CLI::Summary

