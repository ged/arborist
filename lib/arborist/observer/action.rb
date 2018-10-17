# -*- ruby -*-
#encoding: utf-8

require 'schedulability'
require 'loggability'

require 'arborist/observer' unless defined?( Arborist::Observer )


# An action taken by an Observer.
class Arborist::Observer::Action
	extend Loggability


	# Loggability API -- log to the Arborist logger
	log_to :arborist


	### Create a new Action that will call the specified +block+ +during+ the given schedule,
	### but only +after+ the specified number of events have arrived +within+ the given
	### time threshold.
	def initialize( within: 0, after: 1, during: nil, ignore_flapping: false, &block )
		raise ArgumentError, "Action requires a block" unless block

		@block           = block
		@time_threshold  = within
		@schedule        = Schedulability::Schedule.parse( during ) if during
		@ignore_flapping = ignore_flapping

		if within.zero?
			@count_threshold = after
		else
			# It should always be 2 or more if there is a time threshold
			@count_threshold = [ after, 2 ].max
		end

		@event_history = {}
	end


	######
	public
	######

	##
	# The object to #call when the action is triggered.
	attr_reader :block

	##
	# The maximum number of seconds between events that cause the action to be called
	attr_reader :time_threshold

	##
	# The minimum number of events that cause the action to be called when the #time_threshold
	# is met.
	attr_reader :count_threshold

	##
	# The schedule that applies to this action.
	attr_reader	:schedule

	##
	# Take no action if the node the event belongs to is in a flapping
	# state.
	attr_reader	:ignore_flapping

	##
	# The Hash of recent events, keyed by their arrival time.
	attr_reader :event_history


	### Call the action for the specified +event+.
	def handle_event( event )
		self.record_event( event )
		self.call_block( event ) if self.should_run? && ! self.flapping?( event )
	end


	### Execute the action block with the specified +event+.
	###
	def call_block( event )
		if self.block.arity >= 2 || self.block.arity < 0
			self.block.call( event.dup, self.event_history.dup )
		else
			self.block.call( event.dup )
		end
	rescue => err
		self.log.error "Exception while running observer: %s: %s\n%s" % [
			err.class.name,
			err.message,
			err.backtrace.join("\n  ")
		]
	ensure
		self.event_history.clear
	end


	### Record the specified +event+ in the event history if within the scheduled period(s).
	def record_event( event )
		return if self.schedule && !self.schedule.now?
		self.event_history[ Time.now ] = event
		self.event_history.keys.sort.each do |event_time|
			break if self.event_history.size <= self.count_threshold
			self.event_history.delete( event_time )
		end
	end


	### Returns +true+ if the threshold is exceeded and the current time is within the
	### action's schedule.
	def should_run?
		return self.time_threshold_exceeded? && self.count_threshold_exceeded?
	end


	### Returns +true+ if this observer respects the flapping state of
	### a node, and the generated event is attached to a flapping node.
	def flapping?( event )
		return self.ignore_flapping && event[ 'flapping' ]
	end


	### Returns +true+ if the time between the first and last event in the #event_history is
	### less than the #time_threshold.
	def time_threshold_exceeded?
		return true if self.time_threshold.zero?
		return false unless self.count_threshold_exceeded?

		first = self.event_history.keys.min
		last = self.event_history.keys.max

		self.log.debug "Time between the %d events in the record (%p): %0.5fs" %
			[ self.event_history.size, self.event_history, last - first ]
		return last - first <= self.time_threshold
	end


	### Returns +true+ if the number of events in the event history meet or exceed the
	### #count_threshold.
	def count_threshold_exceeded?
		return self.event_history.size >= self.count_threshold
	end

end # class Arborist::Observer::Action
