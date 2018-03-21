# -*- ruby -*-
#encoding: utf-8

require 'arborist/cli' unless defined?( Arborist::CLI )
require 'arborist/node'
require 'arborist/manager'


# Command to reset node states while retaining acknowledgement state.
module Arborist::CLI::Reset
	extend Arborist::CLI::Subcommand

	desc 'Reset all state except for acknowledged/disabled'
	long_desc <<-EOF
		If you've rearranged the dependencies in the tree, existing states may no
		longer be valid.  This command forcefully resets all states to "unknown" so
		they can be re-checked, but retains existing acknowledgements and intentionally
		disabled nodes.  (If you don't care about those you should instead simply delete
		the state file.)

		It's pointless to use this command while the Manager is running.
	EOF

	arg :SOURCE

	command :reset do |cmd|

		cmd.flag :loader, desc: "Specify a loader type to use.",
			default_value: 'file'

		cmd.action do |globals, options, args|
			source  = args.shift
			loader  = Arborist::Loader.create( options[:loader], source )
			manager = Arborist.manager_for( loader )

			manager.nodes.each_pair do |identifier, node|
				next if node.ack || node.operational?
				node.status = 'unknown'
			end

			unless_dryrun( "Resetting node states." ) do
				manager.save_node_states
			end
		end
	end

end # module Arborist::CLI::Reset

