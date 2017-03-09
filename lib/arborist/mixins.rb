# -*- ruby -*-
#encoding: utf-8

require 'ipaddr'

# A collection of generically-useful mixins
module Arborist

	# A collection of methods for declaring other methods.
	#
	#   class MyClass
	#       extend Arborist::MethodUtilities
	#
	#       singleton_attr_accessor :types
	#       singleton_method_alias :kinds, :types
	#   end
	#
	#   MyClass.types = [ :pheno, :proto, :stereo ]
	#   MyClass.kinds # => [:pheno, :proto, :stereo]
	#
	module MethodUtilities

		### Creates instance variables and corresponding methods that return their
		### values for each of the specified +symbols+ in the singleton of the
		### declaring object (e.g., class instance variables and methods if declared
		### in a Class).
		def singleton_attr_reader( *symbols )
			singleton_class.instance_exec( symbols ) do |attrs|
				attr_reader( *attrs )
			end
		end

		### Create instance variables and corresponding methods that return
		### true or false values for each of the specified +symbols+ in the singleton
		### of the declaring object.
		def singleton_predicate_reader( *symbols )
			singleton_class.extend( Arborist::MethodUtilities )
			singleton_class.attr_predicate( *symbols )
		end

		### Creates methods that allow assignment to the attributes of the singleton
		### of the declaring object that correspond to the specified +symbols+.
		def singleton_attr_writer( *symbols )
			singleton_class.instance_exec( symbols ) do |attrs|
				attr_writer( *attrs )
			end
		end

		### Creates readers and writers that allow assignment to the attributes of
		### the singleton of the declaring object that correspond to the specified
		### +symbols+.
		def singleton_attr_accessor( *symbols )
			symbols.each do |sym|
				singleton_class.__send__( :attr_accessor, sym )
			end
		end

		### Create predicate methods and writers that allow assignment to the attributes
		### of the singleton of the declaring object that correspond to the specified
		### +symbols+.
		def singleton_predicate_accessor( *symbols )
			singleton_class.extend( Arborist::MethodUtilities )
			singleton_class.attr_predicate_accessor( *symbols )
		end

		### Creates an alias for the +original+ method named +newname+.
		def singleton_method_alias( newname, original )
			singleton_class.__send__( :alias_method, newname, original )
		end


		### Create a reader in the form of a predicate for the given +attrname+.
		def attr_predicate( attrname )
			attrname = attrname.to_s.chomp( '?' )
			define_method( "#{attrname}?" ) do
				instance_variable_get( "@#{attrname}" ) ? true : false
			end
		end


		### Create a reader in the form of a predicate for the given +attrname+
		### as well as a regular writer method.
		def attr_predicate_accessor( attrname )
			attrname = attrname.to_s.chomp( '?' )
			attr_writer( attrname )
			attr_predicate( attrname )
		end

	end # module MethodUtilities


	# Functions for time calculations
	module TimeFunctions

		###############
		module_function
		###############

		### Calculate the (approximate) number of seconds that are in +count+ of the
		### given +unit+ of time.
		###
		def calculate_seconds( count, unit )
			return case unit
			when :seconds, :second
				count
			when :minutes, :minute
				count * 60
			when :hours, :hour
				count * 3600
			when :days, :day
				count * 86400
			when :weeks, :week
				count * 604800
			when :fortnights, :fortnight
				count * 1209600
			when :months, :month
				count * 2592000
			when :years, :year
				count * 31557600
			else
				raise ArgumentError, "don't know how to calculate seconds in a %p" % [ unit ]
			end
		end
	end # module TimeFunctions


	# Refinements to Numeric and Time to add convenience methods
	module TimeRefinements

		# Approximate Time Constants (in seconds)
		MINUTES = 60
		HOURS   = 60  * MINUTES
		DAYS    = 24  * HOURS
		WEEKS   = 7   * DAYS
		MONTHS  = 30  * DAYS
		YEARS   = 365.25 * DAYS

		refine Numeric do

			### Number of seconds (returns receiver unmodified)
			def seconds
				return self
			end
			alias_method :second, :seconds

			### Returns number of seconds in <receiver> minutes
			def minutes
				return TimeFunctions.calculate_seconds( self, :minutes )
			end
			alias_method :minute, :minutes

			### Returns the number of seconds in <receiver> hours
			def hours
				return TimeFunctions.calculate_seconds( self, :hours )
			end
			alias_method :hour, :hours

			### Returns the number of seconds in <receiver> days
			def days
				return TimeFunctions.calculate_seconds( self, :day )
			end
			alias_method :day, :days

			### Return the number of seconds in <receiver> weeks
			def weeks
				return TimeFunctions.calculate_seconds( self, :weeks )
			end
			alias_method :week, :weeks

			### Returns the number of seconds in <receiver> fortnights
			def fortnights
				return TimeFunctions.calculate_seconds( self, :fortnights )
			end
			alias_method :fortnight, :fortnights

			### Returns the number of seconds in <receiver> months (approximate)
			def months
				return TimeFunctions.calculate_seconds( self, :months )
			end
			alias_method :month, :months

			### Returns the number of seconds in <receiver> years (approximate)
			def years
				return TimeFunctions.calculate_seconds( self, :years )
			end
			alias_method :year, :years


			### Returns the Time <receiver> number of seconds before the
			### specified +time+. E.g., 2.hours.before( header.expiration )
			def before( time )
				return time - self
			end


			### Returns the Time <receiver> number of seconds ago. (e.g.,
			### expiration > 2.hours.ago )
			def ago
				return self.before( ::Time.now )
			end


			### Returns the Time <receiver> number of seconds after the given +time+.
			### E.g., 10.minutes.after( header.expiration )
			def after( time )
				return time + self
			end


			### Return a new Time <receiver> number of seconds from now.
			def from_now
				return self.after( ::Time.now )
			end

		end # refine Numeric


		refine Time do

			### Returns +true+ if the receiver is a Time in the future.
			def future?
				return self > Time.now
			end


			### Returns +true+ if the receiver is a Time in the past.
			def past?
				return self < Time.now
			end


			### Return a description of the receiving Time object in relation to the current
			### time.
			###
			### Example:
			###
			###    "Saved %s ago." % object.updated_at.as_delta
			def as_delta
				now = Time.now
				if now > self
					seconds = now - self
					return "%s ago" % [ timeperiod(seconds) ]
				else
					seconds = self - now
					return "%s from now" % [ timeperiod(seconds) ]
				end
			end


			### Return a description of +seconds+ as the nearest whole unit of time.
			def timeperiod( seconds )
				return case
					when seconds < MINUTES - 5
						'less than a minute'
					when seconds < 50 * MINUTES
						if seconds <= 89
							"a minute"
						else
							"%d minutes" % [ (seconds.to_f / MINUTES).ceil ]
						end
					when seconds < 90 * MINUTES
						'about an hour'
					when seconds < 18 * HOURS
						"%d hours" % [ (seconds.to_f / HOURS).ceil ]
					when seconds < 30 * HOURS
						'about a day'
					when seconds < WEEKS
						"%d days" % [ (seconds.to_f / DAYS).ceil ]
					when seconds < 2 * WEEKS
						'about a week'
					when seconds < 3 * MONTHS
						"%d weeks" % [ (seconds.to_f / WEEKS).round ]
					when seconds < 18 * MONTHS
						"%d months" % [ (seconds.to_f / MONTHS).ceil ]
					else
						"%d years" % [ (seconds.to_f / YEARS).ceil ]
					end
			end

		end # refine Time

	end # module TimeRefinements


	# A collection of utilities for working with Hashes.
	module HashUtilities

		###############
		module_function
		###############

		### Return a version of the given +hash+ with its keys transformed
		### into Strings from whatever they were before.
		def stringify_keys( hash )
			newhash = {}

			hash.each do |key,val|
				if val.is_a?( Hash )
					newhash[ key.to_s ] = stringify_keys( val )
				else
					newhash[ key.to_s ] = val
				end
			end

			return newhash
		end


		### Return a duplicate of the given +hash+ with its identifier-like keys
		### transformed into symbols from whatever they were before.
		def symbolify_keys( hash )
			newhash = {}

			hash.each do |key,val|
				keysym = key.to_s.dup.untaint.to_sym

				if val.is_a?( Hash )
					newhash[ keysym ] = symbolify_keys( val )
				else
					newhash[ keysym ] = val
				end
			end

			return newhash
		end
		alias_method :internify_keys, :symbolify_keys


		### Recursive hash-merge function
		def merge_recursively( key, oldval, newval )
			case oldval
			when Hash
				case newval
				when Hash
					oldval.merge( newval, &method(:merge_recursively) )
				else
					newval
				end

			when Array
				case newval
				when Array
					oldval | newval
				else
					newval
				end

			else
				newval
			end
		end


		### Recursively remove hash pairs in place whose value is nil.
		def compact_hash( hash )
			hash.each_key do |k|
				hash.delete( k ) if hash[ k ].nil?
				compact_hash( hash[k] ) if hash[k].is_a?( Hash )
			end
		end


		### Returns true if the specified +hash+ includes the specified +key+, and the value
		### associated with the +key+ either includes +val+ if it is a Hash, or equals +val+ if it's
		### anything but a Hash.
		def hash_matches( hash, key, val )
			actual = hash[ key ] or return false

			if actual.is_a?( Hash )
				if val.is_a?( Hash )
					return val.all? {|subkey, subval| hash_matches(actual, subkey, subval) }
				else
					return false
				end
			else
				return actual == val
			end
		end

	end # HashUtilities


	# A collection of utilities for working with network addresses, names, etc.
	module NetworkUtilities

		# A union of IPv4 and IPv6 regular expressions.
		IPADDR_RE = Regexp.union(
			IPAddr::RE_IPV4ADDRLIKE,
			IPAddr::RE_IPV6ADDRLIKE_COMPRESSED,
			IPAddr::RE_IPV6ADDRLIKE_FULL
		)


		### Return the specified +address+ as one or more IPAddr objects.
		def normalize_address( address )
			addresses = []
			case address
			when IPAddr
				addresses << address
			when IPADDR_RE
				addresses << IPAddr.new( address )
			when String
				ip_addr = TCPSocket.gethostbyname( address )
				addresses = ip_addr[3..-1].map{|ip| IPAddr.new(ip) }
			else
				raise "I don't know how to parse a %p host address (%p)" %
					[ address.class, address ]
			end

			return addresses
		end

	end # module NetworkUtilities

end # module Arborist
