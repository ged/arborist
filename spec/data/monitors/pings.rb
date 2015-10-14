# -*- ruby -*-
#encoding: utf-8

require 'loggability'
require 'arborist/monitor'
require 'arborist/mixins'

using Arborist::TimeRefinements

module FPingWrapper
	extend Loggability
	log_to :arborist

	def exec_arguments( nodes )
		identifiers = nodes.each_with_object({}) do |(identifier, props), hash|
			next unless props.key?( 'addresses' )
			address = props[ 'addresses' ].first
			hash[ address ] = identifier
		end

		return {} if identifiers.empty?

		return identifiers.keys
	end

	def parse_output( stdout, stderr )
		self.log.debug "Got output: %p" % [ output ]
		# 8.8.8.8 is alive (32.1 ms)
		# 8.8.4.4 is alive (14.9 ms)
		# 8.8.0.1 is unreachable

		return output.each_line.with_object({}) do |line, hash|
			address, remainder = line.split( ' ', 2 )
			identifier = identifiers[ address ] or next

			self.log.debug "  parsing result for %s(%s): %p" % [ identifier, address, remainder ]

			if remainder =~ /is alive \((\d+\.\d+) ms\)/
				hash[ identifier ] = { rtt: Float( $1 ) }
			else
				hash[ identifier ] = { error: remainder.chomp }
			end
		end
	end

end


Arborist::Monitor 'ping check' do
	every 20.seconds
	splay 5.seconds
	match type: 'host'
	exclude tag: :laptop
	use :addresses

	exec 'fping', '-e', '-t', '150'
	exec_callbacks( FPingWrapper )
end

Arborist::Monitor 'ping check downed hosts' do
	every 40.seconds
	splay 15.seconds
	match type: 'host', status: 'down'
	include_down true
	use :addresses

	exec 'fping', '-e', '-t', '150'
	exec_callbacks( FPingWrapper )
end

Arborist::Monitor 'transient host pings' do
	every 5.minutes
	match type: 'host', tag: 'laptop'
	use :addresses

	exec 'fping', '-e', '-t', '500'
	exec_callbacks( FPingWrapper )
end

