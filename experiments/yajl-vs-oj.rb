#!/usr/bin/env ruby
# frozen_string_literals: true

require 'benchmark'
require 'yajl'
require 'oj'

DEFAULT_ITERATIONS = 10_000

json = if (( filename = ARGV.shift ))
		File.read( filename )
	else
		"[]"
	end

iterations = if (( iter = ARGV.shift ))
		iter.to_i
	else
		DEFAULT_ITERATIONS
	end


data = Yajl::Parser.parse( json )
data.freeze

puts "#{iterations} iterations:"
Benchmark.bmbm( 100 ) do |bench|
	bench.report( "Yajl (encode)" ) { iterations.times { Yajl::Encoder.encode(data) } }
	bench.report( "Oj (encode)" ) { iterations.times { Oj.generate(data) } }
	bench.report( "Yajl (decode)" ) { iterations.times { Yajl::Parser.parse(json) } }
	bench.report( "Oj (decode)" ) { iterations.times { Oj.load(json) } }
end


