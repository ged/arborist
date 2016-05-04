# -*- ruby -*-
#encoding: utf-8

require 'set'
require 'time'
require 'loggability'

require 'arborist' unless defined?( Arborist )



# A inter-node dependency that is outside of the implicit ones expressed by the
# tree.
class Arborist::Dependency
	extend Loggability


	# Loggability API -- log to the Arborist logger
	log_to :arborist


	### Construct a new Dependency for the specified +behavior+ on the given +identifiers+
	### with +prefixes+.
	def self::on( behavior, *identifiers, prefixes: nil )
		deps, identifiers = identifiers.flatten.uniq.partition {|obj| obj.is_a?(self.class) }
		prefixes = Array( prefixes ).uniq
		identifiers = prefixes.product( identifiers ).map {|pair| pair.join('-') } unless
			prefixes.empty?

		return self.new( behavior, identifiers + deps )
	end


	### Construct a new instance using the specified +hash+, which should be in the same form
	### as that generated by #to_h:
	###
	###   {
	###     behavior: <string>,
	###     identifiers: [<identifier_1>, <identifier_n>],
	###     subdeps: [<dephash_1>, <dephash_n>],
	###   }
	###
	def self::from_hash( hash )
		self.log.debug "Creating a new %p from a hash: %p" % [ self, hash ]

		hash[:subdeps] ||= []
		subdeps = hash[:subdeps].map {|subhash| self.from_hash(subhash) }

		return self.new( hash[:behavior], hash[:identifiers] + subdeps )
	end


	### Create a new Dependency on the specified +nodes_or_subdeps+ with the given +behavior+
	### (one of :any or :all)
	def initialize( behavior, *nodes_or_subdeps )
		@behavior = behavior
		@subdeps, identifiers = nodes_or_subdeps.flatten.
			partition {|obj| obj.is_a?(self.class) }
		@identifier_states = identifiers.product([ nil ]).to_h
	end


	### Dup constructor -- dup internal datastructures without ephemeral state on #dup.
	def initialize_dup( original ) # :nodoc:
		@subdeps = @subdeps.map( &:dup )
		@identifier_states = @identifier_states.keys.product([ nil ]).to_h
	end


	### Clone constructor -- clone internal datastructures without ephemeral state on #clone.
	def initialize_clone( original ) # :nodoc:
		@subdeps = @subdeps.map( &:clone )
		@identifier_states = @identifier_states.keys.product([ nil ]).to_h
	end


	######
	public
	######

	##
	# The behavior that determines if the dependency is met by any or all of the
	# nodes.
	attr_reader :behavior

	##
	# The Hash of identifier states
	attr_reader :identifier_states

	##
	# The Array of sub-dependencies (instances of Dependency).
	attr_reader :subdeps


	### Return a Set of identifiers belonging to this dependency.
	def identifiers
		return Set.new( self.identifier_states.keys )
	end


	### Return a Set of identifiers which have been marked down in this dependency.
	def down_identifiers
		return Set.new( self.identifier_states.select {|_, mark| mark }.map(&:first) )
	end


	### Return a Set of identifiers which have not been marked down in this dependency.
	def up_identifiers
		return Set.new( self.identifier_states.reject {|_, mark| mark }.map(&:first) )
	end


	### Return a Set of identifiers for all of this Dependency's sub-dependencies.
	def subdep_identifiers
		return self.subdeps.map( &:all_identifiers ).reduce( :+ ) || Set.new
	end


	### Return the Set of this Dependency's identifiers as well as those of all of its
	### sub-dependencies.
	def all_identifiers
		return self.identifiers + self.subdep_identifiers
	end


	### Return any of this dependency's sub-dependencies that are down.
	def down_subdeps
		return self.subdeps.select( &:down? )
	end


	### Return any of this dependency's sub-dependencies that are up.
	def up_subdeps
		return self.subdeps.select( &:up? )
	end


	### Yield each unique identifier and Time of downed nodes from both direct and
	### sub-dependencies.
	def each_downed
		return enum_for( __method__ ) unless block_given?

		yielded = Set.new
		self.identifier_states.each do |ident, time|
			if time
				yield( ident, time ) unless yielded.include?( ident )
				yielded.add( ident )
			end
		end
		self.subdeps.each do |subdep|
			subdep.each_downed do |ident, time|
				if time
					yield( ident, time ) unless yielded.include?( ident )
					yielded.add( ident )
				end
			end
		end
	end


	### Returns +true+ if the receiver includes all of the given +identifiers+.
	def include?( *identifiers )
		return self.all_identifiers.include?( *identifiers )
	end


	### Returns +true+ if this dependency doesn't contain any identifiers or
	### sub-dependencies.
	def empty?
		return self.all_identifiers.empty?
	end


	### Mark the specified +identifier+ as being down and propagate it to any subdependencies.
	def mark_down( identifier, time=Time.now )
		self.identifier_states[ identifier ] = time if self.identifier_states.key?( identifier )
		self.subdeps.each do |dep|
			dep.mark_down( identifier, time )
		end
	end


	### Mark the specified +identifier+ as being up and propagate it to any subdependencies.
	def mark_up( identifier )
		self.subdeps.each do |dep|
			dep.mark_up( identifier )
		end
		self.identifier_states[ identifier ] = nil if self.identifier_states.key?( identifier )
	end


	### Returns +true+ if this dependency cannot be met.
	def down?
		case self.behavior
		when :all
			self.identifier_states.values.any? || self.subdeps.any?( &:down? )
		when :any
			self.identifier_states.values.all? && self.subdeps.all?( &:down? )
		end
	end


	### Returns +true+ if this dependency is met.
	def up?
		return !self.down?
	end


	### Returns the earliest Time a node was marked down.
	def earliest_down_time
		return self.identifier_states.values.compact.min
	end


	### Returns the latest Time a node was marked down.
	def latest_down_time
		return self.identifier_states.values.compact.max
	end


	### Return an English description of why this dependency is not met. If it is
	### met, returns +nil+.
	def down_reason
		ids = self.down_identifiers
		subdeps = self.down_subdeps

		return nil if ids.empty? && subdeps.empty?

		msg = nil
		case self.behavior
		when :all
			msg = ids.first.dup
			if ids.size == 1
				msg << " is down"
			else
				msg << " (and %d other%s) are down" % [ ids.size - 1, ids.size == 2 ? '' : 's' ]
			end

			msg << " as of %s" % [ self.earliest_down_time ]

		when :any
			msg = "%s are all down" % [ ids.to_a.join(', ') ]
			msg << " as of %s" % [ self.latest_down_time ]

		else
			raise "Don't know how to build a description of down behavior for %p" % [ self.behavior ]
		end

		return msg
	end


	### Return the entire dependency tree as a nested Hash.
	def to_h
		return {
			behavior: self.behavior,
			identifiers: self.identifier_states.keys,
			subdeps: self.subdeps.map( &:to_h )
		}
	end


	### Returns true if +other+ is the same object or if they both have the same
	### identifiers, sub-dependencies, and identifier states.
	def eql?( other )
		self.log.debug "Comparing %p to %p (with states)" % [ self, other ]
		return true if other.equal?( self )
		return self == other &&
			self.identifier_states.eql?( other.identifier_states ) &&
			self.subdeps.eql?( other.subdeps )
	end


	### Equality comparison operator -- return true if the +other+ dependency has the same
	### behavior, identifiers, and sub-dependencies. Does not consider identifier states.
	def ==( other )
		return true if other.equal?( self )
		return false unless other.is_a?( self.class )

		return self.behavior == other.behavior &&
			self.identifiers == other.identifiers &&
			self.subdeps == other.subdeps
	end

end # class Arborist::Dependency

