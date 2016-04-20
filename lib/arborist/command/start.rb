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

		cmd.desc "Run under the profiler in the given MODE (one of wall, cpu, or object; defaults to wall)."
		cmd.arg_name :MODE
		cmd.flag [:p, 'profiler'], must_match: ['wall', 'cpu', 'object']

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
				start( runner, options[:p] )
			end
		end
	end


	###############
	module_function
	###############

	### Start the specified +runner+ instance after setting up the environment for
	### it.
	def start( runner, profile_mode=nil )
		Process.setproctitle( runner.class.name )

		if profile_mode
			self.with_profiling_enabled( profile_mode, runner ) do
				runner.run
			end
		else
			runner.run
		end
	end


	### Wrap the profiler around the specified +callable+.
	def self::with_profiling_enabled( profile_arg, runner, &block )
		require 'stackprof'
		mode, outfile = self.parse_profile_args( profile_arg, runner )

		self.log.info "Profiling in %s mode, outputting to %s" % [ mode, outfile ]
		StackProf.run( mode: mode.to_sym, out: outfile, &block )
	rescue LoadError => err
		self.log.debug "%p while loading the StackProf profiler: %s"
		exit_now!( "Couldn't load the profiler; you probably need to `gem install stackprof`", 254 )
	end


	### Set up the StackProf profiler to run in the given +mode+.
	def self::parse_profile_args( arg, runner )
		profile_mode, profile_filename = arg.split( ':', 2 )
		profile_filename ||= self.default_profile_filename( profile_mode, runner )

		return profile_mode, profile_filename
	end


	### Return a filename for a StackProf profile run over the given +runner+.
	def self::default_profile_filename( mode, runner )
		basename = runner.class.name.gsub( /.*::/, '' )
		return "%s-%s-%s.%d.dump" % [
			basename,
			mode,
			Time.now.strftime('%Y%m%d%H%M%S'),
			Process.pid,
		]
	end


end # module Arborist::CLI::Start

