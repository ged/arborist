# -*- ruby -*-
#encoding: utf-8

require 'schedulability'
require 'schedulability/schedule'
require 'loggability'

require 'arborist/observer' unless defined?( Arborist::Observer )


# An summarization action taken by an Observer.
class Arborist::Observer::Summarize
	extend Loggability


	# Loggability API -- log to the Arborist logger
	log_to :arborist


	### Create a new Summary that will call the specified +block+ +during+ the given schedule,
	### +every+ specified number of seconds or +count+ events, whichever is sooner.
	def initialize( every: 0, count: 0, during: nil, &block )
		raise ArgumentError, "Summarize requires a block" unless block
		raise ArgumentError, "Summarize requires a value for `every` or `count`." if
			every.zero? && count.zero?

		@time_threshold  = every
		@count_threshold = count
		@schedule        = Schedulability::Schedule.parse( during ) if during
		@block           = block

		@event_history = {}
	end


	######
	public
	######

	##
	# The object to #call when the action is triggered.
	attr_reader :block

	##
	# The number of seconds between calls to the action
	attr_reader :time_threshold

	##
	# The number of events that cause the action to be called.
	attr_reader :count_threshold

	##
	# The schedule that applies to this action.
	attr_reader	:schedule

	##
	# The Hash of recent events, keyed by their arrival time.
	attr_reader :event_history


	### Call the action for the specified +event+.
	def handle_event( event )
		self.record_event( event )
		self.call_block if self.should_run?
	end


	### Handle a timing event by calling the block with any events in the history.
	def on_timer
		self.log.debug "Timer event: %d pending event/s" % [ self.event_history.size ]
		self.call_block unless self.event_history.empty?
	end


	### Execute the action block.
	def call_block
		self.block.call( self.event_history.dup )
	ensure
		self.event_history.clear
	end


	### Record the specified +event+ in the event history if within the scheduled period(s).
	def record_event( event )
		return if self.schedule && !self.schedule.now?
		self.event_history[ Time.now ] = event
	end


	### Returns +true+ if the count threshold is exceeded and the current time is within the
	### action's schedule.
	def should_run?
		return self.count_threshold_exceeded?
	end


	### Returns +true+ if the number of events in the event history meet or exceed the
	### #count_threshold.
	def count_threshold_exceeded?
		return false if self.count_threshold.zero?
		self.log.debug "Event history has %d events" % [ self.event_history.size ]
		return self.event_history.size >= self.count_threshold
	end

end # class Arborist::Observer::Summarize
