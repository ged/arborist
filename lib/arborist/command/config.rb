# -*- ruby -*-
#encoding: utf-8

require 'arborist/cli' unless defined?( Arborist::CLI )


# Command to dump a basic Arborist config file
module Arborist::CLI::Config
	extend Arborist::CLI::Subcommand

	desc 'Dump a default Arborist config file'
	command :config do |cmd|

		cmd.action do |globals, options, args|
			$stdout.puts Configurability.default_config.dump
		end
	end

end # module Arborist::CLI::Clone

