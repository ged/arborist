# -*- ruby -*-
#encoding: utf-8

require 'loggability'
require 'arborist/monitor'
require 'arborist/mixins'

using Arborist::TimeRefinements

module FPingWrapper
	extend Loggability
	log_to :arborist

	def do_fping( nodes )
		identifiers = nodes.each_with_object({}) do |(identifier, props), hash|
			next unless props.key?( 'addresses' )
			address = props[ 'addresses' ].first
			hash[ address ] = identifier
		end

		return {} if identifiers.empty?

		output = yield( identifiers.keys )
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
	extend FPingWrapper

	every 20.seconds
	splay 5.seconds
	match type: 'host'
	exclude tag: :laptop
	use :addresses

	exec 'fping', '-e', '-t', '150', &method( :do_fping )
end

Arborist::Monitor 'ping check downed hosts' do
	extend FPingWrapper

	every 2.minutes
	splay 15.seconds
	match type: 'host'
	include_down true
	use :addresses

	exec 'fping', '-e', '-t', '150', &method( :do_fping )
end

Arborist::Monitor 'transient host pings' do
	extend FPingWrapper

	match type: 'host', tag: 'laptop'
	use :addresses
	exec 'fping', '-e', '-t', '500', &method( :do_fping )

	every 5.minutes
end

