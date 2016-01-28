# -*- ruby -*-
#encoding: utf-8

require 'msgpack'

require 'arborist/cli' unless defined?( Arborist::CLI )
require 'arborist/client'

# Command to watch events in an Arborist manager.
module Arborist::CLI::Watch
	extend Arborist::CLI::Subcommand

	desc 'Watch events in an Arborist manager'

	command :watch do |cmd|
		cmd.action do |globals, options, args|
			client = Arborist::Client.new
			subid  = client.subscribe( identifier: '_' )

			sock = client.event_api
			sock.subscribe( subid )
			prompt.say "Subscription %p" % [ subid ]

			begin
				prompt.say "Watching for events on manager at %s" % [ client.event_api_url ]
				loop do
					msgsubid = sock.recv
					raise "Partial write?!" unless sock.rcvmore?
					raw_event = sock.recv

					event = MessagePack.unpack( raw_event )
					prompt.say "[%s] %s\n" % [
						hl(Time.now.strftime('%Y-%m-%d %H:%M:%S %Z')).color(:dark, :white),
						hl(dump_event( event )).color( :dark, :white )
					]
				end
			ensure
				client.unsubscribe( subid )
			end
		end
	end


	###############
	module_function
	###############

	### Return a String representation of the specified +event+.
	def dump_event( event )
		event_type = event['type']
		id = event['identifier']

		case event_type
		when 'node.update'
			type, status, error = event['data'].values_at( *%w'type status error' )
			return "%s updated: %s is %s%s" % [
				hl( id ).color( :cyan ),
				type,
				hl( status ).color( status.to_sym ),
				error ? " (#{error})" : ''
			]
		when 'node.delta'
			pairs = diff_pairs( event['data'] )
			return "%s delta, changes: %s" % [ hl( id ).color( :cyan ), pairs ]
		else
			return "%s event: %p" % [ hl(event_type).color(:dark, :white), event ]
		end
	end


	### Return a string showing the differences in a delta event's change +data+.
	def diff_pairs( data )
		return data.collect do |key, pairs|
			if pairs.is_a?( Hash )
				diff_pairs( pairs )
			else
				val1, val2 = *pairs
				"%s: %s -> %s" % [
					hl( key ).color( :dark, :white ),
					hl( val1 ).color( :yellow ),
					hl( val2 ).color( :bold, :yellow )
				]
			end
		end.join( hl(", ").color(:dark, :white) )
	end

end # module Arborist::CLI::Watch

