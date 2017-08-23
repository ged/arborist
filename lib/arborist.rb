# -*- ruby -*-
#encoding: utf-8

require 'cztop'

require 'pathname'
require 'configurability'
require 'loggability'


# Arborist namespace
module Arborist
	extend Loggability,
	       Configurability

	# Package version
	VERSION = '0.1.0'

	# Version control revision
	REVISION = %q$Revision$


	# The name of the environment variable which can be used to set the config path
	CONFIG_ENV = 'ARBORIST_CONFIG'

	# The name of the config file for local overrides.
	LOCAL_CONFIG_FILE = Pathname( '~/.arborist.yml' ).expand_path

	# The name of the config file that's loaded if none is specified.
	DEFAULT_CONFIG_FILE = Pathname( 'arborist.yml' ).expand_path


	##
	# Set up a logger for the Arborist namespace
	log_as :arborist

	# Configurability API -- use the 'arborist'
	configurability( :arborist ) do

		##
		# The ZMQ REP socket for the API for accessing the node tree.
		setting :tree_api_url, default: 'ipc:///tmp/arborist_tree.sock'

		##
		# The ZMQ PUB socket for published events
		setting :event_api_url, default: 'ipc:///tmp/arborist_events.sock'

	end


	require 'arborist/mixins'
	extend Arborist::MethodUtilities


	#
	# :section: Configuration API
	#

	### Get the loaded config (a Configurability::Config object)
	def self::config
		Configurability.loaded_config
	end


	### Returns +true+ if the configuration has been loaded at least once.
	def self::config_loaded?
		return self.config ? true : false
	end


	### Load the specified +config_file+, install the config in all objects with
	### Configurability, and call any callbacks registered via #after_configure.
	def self::load_config( config_file=nil, defaults=nil )
		config_file ||= ENV[ CONFIG_ENV ]
		config_file ||= LOCAL_CONFIG_FILE if LOCAL_CONFIG_FILE.exist?
		config_file ||= DEFAULT_CONFIG_FILE

		defaults    ||= Configurability.gather_defaults

		self.log.info "Loading config from %p with defaults for sections: %p." %
			[ config_file, defaults.keys ]
		config = Configurability::Config.load( config_file, defaults )

		config.install
	end


	### Add a constructor function to the Arborist namespace called +name+
	### with the specified +method_body+.
	def self::add_dsl_constructor( subclass, &method_body )
		name = subclass.name

		if name
			name.sub!( /.*::/, '' )
			self.log.debug "Adding factory method for %p: %p" % [ name, method_body ]
			singleton_class.instance_exec( name, method_body ) do |name, body|
				define_method( name, &body )
			end
		else
			self.log.info "Skipping DSL constructor for anonymous class."
		end
	end


	### Return a new Arborist::Manager for the nodes loaded by the specified +loader+.
	def self::manager_for( loader )
		self.load_all
		nodes = Arborist::Node.each_in( loader )
		manager = Arborist::Manager.new
		manager.load_tree( nodes )

		return manager
	end


	### Return a new Arborist::MonitorRunner for the monitors described in files under
	### the specified +loader+.
	def self::monitor_runner_for( loader )
		self.load_all
		monitors = Arborist::Monitor.each_in( loader )
		runner = Arborist::MonitorRunner.new
		runner.load_monitors( monitors )

		return runner
	end


	### Return a new Arborist::ObserverRunner for the observers described in files under
	### the specified +loader+.
	def self::observer_runner_for( loader )
		self.load_all
		observers = Arborist::Observer.each_in( loader )
		runner = Arborist::ObserverRunner.new
		runner.load_observers( observers )

		return runner
	end


	### Load all node and event types
	def self::load_all
		Arborist::Node.load_all
	end


	require 'arborist/exceptions'
	require 'arborist/mixins'

	autoload :Client, 'arborist/client'
	autoload :Event, 'arborist/event'
	autoload :Loader, 'arborist/loader'
	autoload :Manager, 'arborist/manager'
	autoload :Monitor, 'arborist/monitor'
	autoload :MonitorRunner, 'arborist/monitor_runner'
	autoload :Node, 'arborist/node'
	autoload :Observer, 'arborist/observer'
	autoload :ObserverRunner, 'arborist/observer_runner'
	autoload :Subscription, 'arborist/subscription'

end # module Arborist

