# -*- ruby -*-
#encoding: utf-8

require 'etc'

require 'arborist/cli' unless defined?( Arborist::CLI )
require 'arborist/client'

# Command to ack a node
module Arborist::CLI::Ack
	extend Arborist::CLI::Subcommand

	desc 'Ack/disable one or more nodes in the Arborist tree'

	arg :IDENTIFIER, optional: true, multiple: true

	command :ack do |cmd|

		cmd.switch :clear, default: false,
			desc: "Clear the ack instead of setting it.",
			negatable: false
		cmd.switch [ :k, 'keep-going' ], default: false,
			desc: "Continue in the event of errors.",
			negatable: false

		cmd.flag [ :u, :user ],
			desc: "The user to mark the nodes with."
		cmd.flag [ :m, :message ],
			desc: "The acknowledgement message."

		cmd.action do |globals, options, args|
			identifiers = get_identifiers( args )
			help_now!( "No node identifiers supplied." ) if identifiers.empty?

			client = Arborist::Client.new
			res = {}

			if options[ :clear ]
				identifiers.each do |id|
					res[ id ] = client.clear_ack( identifier: id )
				end

			else
				message = options[ :message ] || prompt.ask( "Ack/disable message:" )
				help_now!( "A acknowlegement/disable message is required." ) unless message

				userid = options[ :user ] || prompt.ask( "Your name?", default: Etc.getpwuid.name )
				help_now!( "Unable to determine ack user." ) unless userid

				identifiers.each do |id|
					res[ id ] = unless_dryrun( "Acking #{id}...", true ) do
						begin
							client.ack(
								identifier: id,
								message:    message,
								sender:     userid,
								via:        "command line"
							)
						rescue => err
							raise unless options[ 'keep-going' ]
							err.message
						end
					end
				end
			end

			res.each_pair do |identifier, result|
				prompt.say "%s: %s" % [
					hl.bold.bright_blue( identifier ),
					result == true ? "Okay." : hl.red( res[identifier].to_s )
				]
			end
		end
	end


	###############
	module_function
	###############

	### Parse a list of identifiers from the command line or from
	### a multiline prompt.
	def get_identifiers( args )
		identifiers = args
		if args.empty?
			identifiers = prompt.multiline( "Enter node identifiers, separated with newlines or commas:" )
			identifiers = identifiers.map( &:chomp ).map{|id| id.split(/,\s*/) }.flatten
		end

		return identifiers.uniq
	end

end # module Arborist::CLI::Ack

