# -*- ruby -*-
#encoding: utf-8

require 'arborist/cli' unless defined?( Arborist::CLI )
require 'arborist/client'

# Command to start an interactive client session.
module Arborist::CLI::Client
	extend Arborist::CLI::Subcommand

	desc 'Start an interactive client session'
	long_desc <<-EOF
	Starts a pry session in an Arborist::Client context.
	EOF

	command :client do |cmd|
		cmd.action do |globals, options, args|
			begin
				require 'pry'
			rescue LoadError => err
				self.log.debug( err )
				exit_now! "This command requires the 'pry' gem."
			end

			client = Arborist::Client.new
			Pry.config.prompt_name = "arborist %s> " % [ Arborist.tree_api_url ]
			Pry.pry( client )
		end
	end

end # module Arborist::CLI::Client

