# -*- ruby -*-
#encoding: utf-8

require 'loggability'
require 'tty'
require 'pastel'
require 'gli'

require 'arborist' unless defined?( Arborist )
require 'arborist/mixins'


# The command-line interface to Arborist.
module Arborist::CLI
	extend Arborist::MethodUtilities,
	       Loggability,
	       GLI::App


	# Write logs to Arborist's logger
	log_to :arborist


	#
	# GLI
	#

	# Set up global[:description] and options
	program_desc 'Arborist'

	# The command version
	version Arborist::VERSION

	# Use an OpenStruct for options instead of a Hash
	# use_openstruct( true )

	# Subcommand options are independent of global[:ones]
	subcommand_option_handling :normal

	# Strict argument validation
	arguments :strict


	# Custom parameter types
	accept Array do |value|
		value.strip.split(/\s*,\s*/)
	end
	accept Pathname do |value|
		Pathname( value.strip )
	end


	# Global options
	desc "Load the specified CONFIGFILE."
	arg_name :CONFIGFILE
	flag [:c, :config], type: Pathname

	desc 'Enable debugging output'
	switch [:d, :debug]

	desc 'Enable verbose output'
	switch [:v, :verbose]

	desc 'Set log level to LEVEL (one of %s)' % [Loggability::LOG_LEVELS.keys.join(', ')]
	arg_name :LEVEL
	flag [:l, :loglevel], must_match: Loggability::LOG_LEVELS.keys

	desc "Don't actually do anything, just show what would happen."
	switch [:n, 'dry-run']

	desc "Additional Ruby libs to require before doing anything."
	flag [:r, 'requires'], type: Array


	#
	# GLI Event callbacks
	#

	# Set up global options
	pre do |global, command, options, args|
		self.set_logging_level( global[:l] )

		# Include a 'lib' directory if there is one
		$LOAD_PATH.unshift( 'lib' ) if File.directory?( 'lib' )

		self.require_additional_libs( global[:r] ) if global[:r]
		self.load_config( global )
		self.set_logging_level( global[:l] ) if global[:l] # again; override config file

		self.setup_pastel_aliases
		self.setup_output( global )

		true
	end


	# Write the error to the log on exceptions.
	on_error do |exception|
		case exception
		when OptionParser::ParseError, GLI::CustomExit
			self.log.debug( exception )
		else
			self.log.error( exception )
		end

		exception.backtrace.each {|frame| self.log.debug(frame) }

		true
	end




	##
	# Registered subcommand modules
	singleton_attr_accessor :subcommand_modules


	### Overridden -- Add registered subcommands immediately before running.
	def self::run( * )
		self.add_registered_subcommands
		super
	end


	### Add the specified +mod+ule containing subcommands to the 'arborist' command.
	def self::register_subcommands( mod )
		self.subcommand_modules ||= []
		self.subcommand_modules.push( mod )
		mod.extend( GLI::DSL, GLI::AppSupport, Loggability )
		mod.log_to( :arborist )
	end


	### Add the commands from the registered subcommand modules.
	def self::add_registered_subcommands
		self.subcommand_modules ||= []
		self.subcommand_modules.each do |mod|
			merged_commands = mod.commands.merge( self.commands )
			self.commands.update( merged_commands )
			command_objs = self.commands_declaration_order | self.commands.values
			self.commands_declaration_order.replace( command_objs )
		end
	end


	### Return the Pastel colorizer.
	###
	def self::pastel
		@pastel ||= Pastel.new( enabled: $stdout.tty? )
	end


	### Return the TTY prompt used by the command to communicate with the
	### user.
	def self::prompt
		@prompt ||= TTY::Prompt.new
	end


	### Discard the existing HighLine prompt object if one existed. Mostly useful for
	### testing.
	def self::reset_prompt
		@prompt = nil
	end


	### Set the global logging +level+ if it's defined.
	def self::set_logging_level( level=nil )
		if level
			Loggability.level = level.to_sym
		else
			Loggability.level = :fatal
		end
	end


	### Load any additional Ruby libraries given with the -r global option.
	def self::require_additional_libs( requires)
		requires.each do |path|
			path = "arborist/#{path}" unless path.start_with?( 'arborist/' )
			require( path )
		end
	end


	### Setup pastel color aliases
	###
	def self::setup_pastel_aliases
		self.pastel.alias_color( :headline, :bold, :white, :on_black )
		self.pastel.alias_color( :success, :bold, :green )
		self.pastel.alias_color( :error, :bold, :red )
		self.pastel.alias_color( :up, :green )
		self.pastel.alias_color( :down, :red )
		self.pastel.alias_color( :unknown, :dark, :yellow )
		self.pastel.alias_color( :disabled, :dark, :white )
		self.pastel.alias_color( :quieted, :dark, :green )
		self.pastel.alias_color( :acked, :yellow )
		self.pastel.alias_color( :warn, :bold, :magenta )
		self.pastel.alias_color( :highlight, :bold, :yellow )
		self.pastel.alias_color( :search_hit, :black, :on_white )
		self.pastel.alias_color( :prompt, :cyan )
		self.pastel.alias_color( :even_row, :bold )
		self.pastel.alias_color( :odd_row, :reset )
	end


	### Load the config file using either arborist-base's config-loader if available, or
	### fall back to DEFAULT_CONFIG_FILE
	def self::load_config( global={} )
		Arborist.load_config( global[:c] ) if global[:c]

		# Set up the logging formatter
		Loggability.format_with( :color ) if $stdout.tty?
	end


	### Set up the output levels and globals based on the associated +global+ options.
	def self::setup_output( global )

		# Turn on Ruby debugging and/or verbosity if specified
		if global[:n]
			$DRYRUN = true
			Loggability.level = :warn
		else
			$DRYRUN = false
		end

		if global[:verbose]
			$VERBOSE = true
			Loggability.level = :info
		end

		if global[:debug]
			$DEBUG = true
			Loggability.level = :debug
		end
	end


	#
	# GLI subcommands
	#


	# Convenience module for subcommand registration syntax sugar.
	module Subcommand

		### Extension callback -- register the extending object as a subcommand.
		def self::extended( mod )
			Arborist::CLI.log.debug "Registering subcommands from %p" % [ mod ]
			Arborist::CLI.register_subcommands( mod )
		end


		###############
		module_function
		###############

		### Exit with the specified +exit_code+ after printing the given +message+.
		def exit_now!( message, exit_code=1 )
			raise GLI::CustomExit.new( message, exit_code )
		end


		### Exit with a helpful +message+ and display the usage.
		def help_now!( message=nil )
			exception = OptionParser::ParseError.new( message )
			def exception.exit_code; 64; end

			raise exception
		end


		### Get the prompt (a TTY::Prompt object)
		def prompt
			return Arborist::CLI.prompt
		end


		### Return the global Pastel object for convenient formatting, color, etc.
		def hl
			return Arborist::CLI.pastel
		end


		### Return the specified +string+ in the 'headline' ANSI color.
		def headline_string( string )
			return hl.headline( string )
		end


		### Return the specified +string+ in the 'highlight' ANSI color.
		def highlight_string( string )
			return hl.highlight( string )
		end


		### Return the specified +string+ in the 'success' ANSI color.
		def success_string( string )
			return hl.success( string )
		end


		### Return the specified +string+ in the 'error' ANSI color.
		def error_string( string )
			return hl.error( string )
		end


		### Output a table with the given +header+ (an array) and +rows+
		### (an array of arrays).
		def display_table( header, rows )
			table = TTY::Table.new( header, rows )
			renderer = nil

			if hl.enabled?
				renderer = TTY::Table::Renderer::Unicode.new(
					table,
					multiline: true,
					padding: [0,1,0,1]
				)
				renderer.border.style = :dim

			else
				renderer = TTY::Table::Renderer::ASCII.new(
					table,
					multiline: true,
					padding: [0,1,0,1]
				)
			end

			puts renderer.render
		end


		### Return the count of visible (i.e., non-control) characters in the given +string+.
		def visible_chars( string )
			return string.to_s.gsub(/\e\[.*?m/, '').scan( /\P{Cntrl}/ ).size
		end


		### In dry-run mode, output the description instead of running the provided block and
		### return the +return_value+.
		### If dry-run mode is not enabled, yield to the block.
		def unless_dryrun( description, return_value=true )
			if $DRYRUN
				self.log.warn( "DRYRUN> #{description}" )
				return return_value
			else
				return yield
			end
		end
		alias_method :unless_dry_run, :unless_dryrun

	end # module Subcommand


	### Load commands from any files in the specified directory relative to LOAD_PATHs
	def self::commands_from( subdir )
		Gem.find_latest_files( File.join(subdir, '*.rb') ).each do |rbfile|
			self.log.debug "  loading %s..." % [ rbfile ]
			require( rbfile )
		end
	end


	commands_from 'arborist/command'

end # class Arborist::CLI
