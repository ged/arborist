# -*- ruby -*-
#encoding: utf-8

require 'loggability'
require 'highline'
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


	# Make a HighLine color scheme
	COLOR_SCHEME = HighLine::ColorScheme.new do |scheme|
		scheme[:header]    = [ :bold, :yellow ]
		scheme[:subheader] = [ :bold, :white ]
		scheme[:key]       = [ :white ]
		scheme[:value]     = [ :bold, :white ]
		scheme[:error]     = [ :red ]
		scheme[:warning]   = [ :yellow ]
		scheme[:message]   = [ :reset ]
	end


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
	default_value Loggability[self].level
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
		self.install_highline_colorscheme

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

	##
	# The IO opened to the output file
	singleton_attr_accessor :outfile


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


	### Return the HighLine prompt used by the command to communicate with the
	### user.
	def self::prompt
		@prompt ||= HighLine.new( $stdin, $stderr )
	end


	### If the command's output was redirected to a file, return the open File object
	### for it.
	def self::outfile
		return @outfile
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


	### Install the color scheme used by HighLine
	def self::install_highline_colorscheme
		HighLine.color_scheme = HighLine::ColorScheme.new do |cs|
			cs[:headline]   = [ :bold, :white, :on_black ]
			cs[:success]    = [ :bold, :green ]
			cs[:error]      = [ :bold, :red ]
			cs[:up]         = [ :green ]
			cs[:down]       = [ :red ]
			cs[:unknown]    = [ :dark, :yellow ]
			cs[:disabled]   = [ :dark, :white ]
			cs[:quieted]    = [ :dark, :green ]
			cs[:acked]      = [ :yellow ]
			cs[:highlight]  = [ :bold, :yellow ]
			cs[:search_hit] = [ :black, :on_white ]
			cs[:prompt]     = [ :cyan ]
			cs[:even_row]   = [ :bold ]
			cs[:odd_row]    = [ :normal ]
		end
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


		### Get the prompt (a Highline object)
		def prompt
			return Arborist::CLI.prompt
		end


		### Return the specified +text+ as a Highline::String for convenient formatting,
		### color, etc.
		def hl( text )
			return HighLine::String.new( text.to_s )
		end


		### Return the specified +string+ in the 'headline' ANSI color.
		def headline_string( string )
			return hl( string ).color( :headline )
		end


		### Return the specified +string+ in the 'highlight' ANSI color.
		def highlight_string( string )
			return hl( string ).color( :highlight )
		end


		### Return the specified +string+ in the 'success' ANSI color.
		def success_string( string )
			return hl( string ).color( :success )
		end


		### Return the specified +string+ in the 'error' ANSI color.
		def error_string( string )
			return hl( string ).color( :error )
		end


		### Output a table with the given +rows+.
		def display_table( rows )
			colwidths = rows.transpose.map do |colvals|
				colvals.map {|val| visible_chars(val) }.max
			end

			rows.each do |row|
				row_string = row.zip( colwidths ).inject( '' ) do |accum, (val, colsize)|
					padding = ' ' * (colsize - visible_chars(val) + 2)
					accum + val.to_s + padding
				end

				Arborist::CLI.prompt.say( row_string + "\n" )
			end
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


	### Register one or more subcommands with the 'arborist' command shell. The given
	### block will be evaluated in the context of Arborist::CLI.
	def self::register( &block )
		self.instance_eval( &block )
	end


	### Custom command loader. The default one is silly.
	def self::load_commands( path )
		self.log.debug "Load commands from %s" % [ path ]
		Pathname.glob( path + '*.rb' ).each do |rbfile|
			self.log.debug "  loading %s..." % [ rbfile ]
			require( rbfile )
		end
	end


	# Load commands from any files in the specified directory relative to LOAD_PATHs
	def self::commands_from( subdir )
		$LOAD_PATH.map {|path| Pathname(path) }.each do |libdir|
			command_dir = libdir.expand_path + subdir
			load_commands( command_dir )
		end
	end


	commands_from 'arborist/command'

end # class Arborist::CLI
