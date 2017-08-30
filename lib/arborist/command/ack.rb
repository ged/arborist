# -*- ruby -*-
#encoding: utf-8

require 'pp'

require 'arborist/cli' unless defined?( Arborist::CLI )
require 'arborist/client'

# Command to ack a node
module Arborist::CLI::Tree
	extend Arborist::CLI::Subcommand


	desc 'Ack a node in the Arborist tree'

	arg :IDENTIFIER
	arg :USERID, optional: true
	arg :MESSAGE, optional: true

	command :ack do |cmd|

		cmd.switch :clear, default: false,
			desc: "Clear the ack instead of setting it."

		cmd.action do |globals, options, args|
			clearmode = options[:clear]

			identifier = args.shift or help_now!( "No node identifier specified!" )
			client = Arborist::Client.new

			if clearmode
				res = client.clear_ack( identifier )
			else
				userid = args.shift or help_now!( "No user ID specified!" )
				message = args.shift or help_now!( "No ack message given!" )

				res = client.ack( identifier, message, userid, "command line" )
			end

			if res
				prompt.say "Done."
			else
				prompt.say "Hmmm... that returned %p" % [ res ]
			end
		end

	end

end # module Arborist::CLI::Tree

