# -*- ruby -*-
#encoding: utf-8

require 'pathname'
require 'configurability'
require 'loggability'


# Arborist namespace
module Arborist
	extend Loggability,
	       Configurability

	# Package version
	VERSION = '0.0.1'

	# Version control revision
	REVISION = %q$Revision$


	# The name of the environment variable which can be used to set the config path
	CONFIG_ENV = 'ARBORIST_CONFIG'

	# The name of the config file for local overrides.
	LOCAL_CONFIG_FILE = Pathname( '~/.arborist.yml' ).expand_path

	# The name of the config file that's loaded if none is specified.
	DEFAULT_CONFIG_FILE = Pathname( 'arborist.yml' ).expand_path

	# Configurability API -- default configuration values
	CONFIG_DEFAULTS = {
		tree_api_url:  'ipc:///tmp/arborist_tree.sock',
		event_api_url: 'ipc:///tmp/arborist_events.sock'
	}


	##
	# Set up a logger for the Arborist namespace
	log_as :arborist

	# Configurability API -- use the 'arborist'
	config_key :arborist


	require 'arborist/mixins'
	extend Arborist::MethodUtilities


	##
	# The ZMQ REP socket for the API for accessing the node tree.
	singleton_attr_accessor :tree_api_url

	##
	# The ZMQ PUB socket for published events
	singleton_attr_accessor :event_api_url


	#
	# :section: Configuration API
	#

	### Configurability API.
	def self::configure( config=nil )
		config = self.defaults.merge( config || {} )

		self.tree_api_url  = config[ :tree_api_url ]
		self.event_api_url = config[ :event_api_url ]
	end


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
	def self::add_dsl_constructor( name, &method_body )
		self.log.debug "Adding constructor for %p: %p" % [ name, method_body ]
		singleton_class.instance_exec( name, method_body ) do |name, body|
			define_method( name, &body )
		end
	end


	### Return a new Arborist::Manager for the nodes described in files under
	### the specified +directory+.
	def self::manager_for( directory )
		self.load_all
		nodes = Arborist::Node.each_in( directory )
		manager = Arborist::Manager.new
		manager.load_tree( nodes )

		return manager
	end


	### Load all node and event types
	def self::load_all
		Arborist::Node.load_all
		Arborist::Event.load_all
	end


	### Destroy any existing ZMQ state.
	def self::reset_zmq_context
		@zmq_context.destroy if @zmq_context.respond_to?( :destroy )
		@zmq_context = nil
	end


	### Fetch the ZMQ context for Arborist.
	def self::zmq_context
		return @zmq_context ||= ZMQ::Context.new
	end


	require 'arborist/exceptions'
	require 'arborist/mixins'
	require 'arborist/manager'
	require 'arborist/node'
	require 'arborist/event'

end # module Arborist

