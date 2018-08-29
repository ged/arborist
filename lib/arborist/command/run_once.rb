# -*- ruby -*-
#encoding: utf-8

require 'tty-screen'
require 'arborist/cli' unless defined?( Arborist::CLI )


# Command to run a monitor in single-run mode
module Arborist::CLI::RunOnce
	extend Arborist::CLI::Subcommand

	desc 'Run an Arborist monitor once'
	long_desc <<-EOF
	Run monitor(s) once.

	If the MONITOR argument is a file, it is loaded and any monitors contained
	in it are run once and their output is dumped. If it is not a readable file,
	it is assumed to be the name of a monitor callback module, and that is
	run inside of a simple monitor object instead.
	EOF

	arg :MONITOR

	command :run_once do |cmd|

		cmd.flag :type,
			desc: "Specify the types of nodes to run a monitor class against. Ignored for monitor files.",
			default_value: 'host'
		cmd.flag :require, desc: "Require a file before instantiating monitor(s)."

		cmd.action do |globals, options, args|
			monitors = monitors_from_args( args, options )
			client = Arborist.client

			monitors.each do |monitor|
				# :TODO: Should the client maybe have a method for searching for the nodes for a
				#        monitor instead of having to stitch them together like this?
				nodes = client.search(
					criteria: monitor.positive_criteria,
					exclude: monitor.negative_criteria,
					exclude_down: monitor.exclude_down?,
					properties: monitor.node_properties
				)

				desc = "running %p against %d nodes" % [ monitor, nodes.length ]
				unless_dryrun( desc ) do
					prompt.say( highlight_string(monitor.description) )
					results = monitor.run( nodes )
					display_results( results )
				end

			end
		end
	end


	###############
	module_function
	###############


	### Figure out what kind of monitor is being run from the provided +args+ and
	### +options+ and return instances of them.
	def monitors_from_args( args, options )
		return args.flat_map do |monitor|
			if File.exist?( monitor )
				Arborist::Monitor.load( monitor )
			else
				wrap_monitor_callback( monitor, options )
			end
		end
	end


	### Try to load the monitor callback with the specified +mod_name+ and return
	### it inside a plain monitor object.
	def wrap_monitor_callback( mod_name, options )
		filename = fileize( mod_name )
		required_file = options[ :require ] || "arborist/monitor/%s" % [ filename ]
		self.log.debug "Loading monitor callback from %p" % [ required_file ]

		require( required_file )

		exec_module = Arborist::Monitor.const_get( mod_name )
		monitor = Arborist::Monitor.new( exec_module.name, filename )
		monitor.exec( exec_module )
		monitor.match( type: options[:type] )

		return [ monitor ]
	end


	### Return the specified +mod_name+ as the corresponding file name.
	def fileize( mod_name )
		return mod_name.sub( /.*::/, '' ).
			gsub( /([a-z0-9])([A-Z])/, '\\1_\\2' ).downcase
	end


	### Display the results of running a monitor.
	def display_results( results )
		width = TTY::Screen.width

		results.keys.sort.each do |identifier|
			result = results[ identifier ]
			prompt.say( highlight_string(identifier) )
			prompt.say( PP.pp(result, '', width) )
			prompt.say "\n"
		end
	end

end # module Arborist::CLI::Start

