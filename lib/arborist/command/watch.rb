# -*- ruby -*-
#encoding: utf-8

require 'msgpack'

require 'arborist/cli' unless defined?( Arborist::CLI )
require 'arborist/client'

# Command to watch events in an Arborist manager.
module Arborist::CLI::Watch
	extend Arborist::CLI::Subcommand

	HEARTBEAT_CHARACTERS = %w[💓 💗]

	desc 'Watch events in an Arborist manager'

	command :watch do |cmd|
		cmd.action do |globals, options, args|
			client = Arborist::Client.new
			sock = client.event_api

			subid = subscribe_to_node_events( client )
			prompt.say "Subscription %p" % [ subid ]

			# Watch for system events as well
			prompt.say "Subscribing to manager heartbeat events."
			sock.subscribe( 'sys.heartbeat' )

			begin
				last_runid = nil
				prompt.say "Watching for events on manager at %s" % [ client.event_api_url ]
				loop do
					msgsubid = sock.recv
					raise "Partial write?!" unless sock.rcvmore?
					raw_event = sock.recv
					event = MessagePack.unpack( raw_event )

					case msgsubid
					when 'sys.heartbeat'
						this_runid = event['run_id']

						if last_runid && last_runid != this_runid
							self.log.warn "Manager restart: re-subscribing."
							sock.unsubscribe( subid )
							subid = subscribe_to_node_events( client )
							prompt.say "New subscription %p" % [ subid ]
						else
							self.log.debug "Manager is alive (runid: %s)" % [ this_runid ]
						end

						$stderr.print( heartbeat() )
						last_runid = this_runid
					when 'sys.node_added'
						prompt.say "[%s] «Node added» %s\n" % [
							hl(Time.now.strftime('%Y-%m-%d %H:%M:%S %Z')).color(:dark, :white),
							hl(event['node']).color( :bold, :cyan )
						]
					when 'sys.node_removed'
						prompt.say "[%s] »Node removed« %s\n" % [
							hl(Time.now.strftime('%Y-%m-%d %H:%M:%S %Z')).color(:dark, :white),
							hl(event['node']).color( :dark, :cyan )
						]
					else
						prompt.say "[%s] %s\n" % [
							hl(Time.now.strftime('%Y-%m-%d %H:%M:%S %Z')).color(:dark, :white),
							hl(dump_event( event )).color( :dark, :white )
						]
					end
				end
			ensure
				self.log.info "Unsubscribing from subscription %p" % [ subid ]
				client.unsubscribe( subid )
			end
		end
	end


	###############
	module_function
	###############

	### Establish a subscription to all node events via the specified +client+.
	def subscribe_to_node_events( client )
		subid = client.subscribe( identifier: '_' )
		sock = client.event_api

		sock.subscribe( subid )
		return subid
	end


	### Return a String representation of the specified +event+.
	def dump_event( event )
		event_type = event['type']
		id = event['identifier']

		case event_type
		when 'node.update'
			type, status, errors = event['data'].values_at( *%w'type status errors' )
			return "%s updated: %s is %s%s" % [
				hl( id ).color( :cyan ),
				type,
				hl( status ).color( status.to_sym ),
				errors ? " (#{errors})" : ''
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


	### Return a heartbeat string for the current time.
	def heartbeat
		idx = (Time.now.to_i % HEARTBEAT_CHARACTERS.length) - 1
		return " " + HEARTBEAT_CHARACTERS[ idx ] + "\x08\x08"
	end

end # module Arborist::CLI::Watch

