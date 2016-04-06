# -*- ruby -*-
#encoding: utf-8

require 'arborist/cli' unless defined?( Arborist::CLI )


# Command to start a Arborist daemon
module Arborist::CLI::Start
	extend Arborist::CLI::Subcommand

	desc 'Start an Arborist daemon'
	long_desc <<-EOF
	Start the Arborist manager, observers, or monitors. The SOURCE is
	passed to the loader to tell it where to load things from.
	EOF

	arg :DAEMON
	arg :SOURCE

	command :start do |cmd|

		cmd.flag :loader, desc: "Specify a loader type to use.",
			default_value: 'file'

		cmd.action do |globals, options, args|
			appname = args.shift
			source  = args.shift

			loader = Arborist::Loader.create( options[:loader], source )
			runner = case appname
				when 'manager'
					Arborist.manager_for( loader )
				when 'monitors'
					Arborist.monitor_runner_for( loader )
				when 'observers'
					Arborist.observer_runner_for( loader )
				else
					raise "Don't know how to start %p" % [ appname ]
				end

			unless_dryrun( "starting #{appname}" ) do
				start( runner )
			end
		end
	end


	###############
	module_function
	###############

	### Start the specified +runner+ instance after setting up the environment for
	### it.
	def start( runner )
		$0 = runner.class.name
		runner.run
	end

end # module Arborist::CLI::Start

