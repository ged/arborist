#!/usr/bin/env ruby

module Callbacks

	def a_callback
		puts "Called the callback; self is: %p" % [self ]
	end

end


block_callback = Proc.new {
	puts "In the block callback, self is: %p" % [ self ]
}

class MonitorRun; end

obj = MonitorRun.new
obj.extend( Callbacks )
obj.a_callback

obj.instance_exec( block_callback ) do |cb|
	eval( &block_callback )
end



