#!/usr/bin/ruby -*- ruby -*-

require 'bundler/setup'
require 'configurability'
require 'loggability'
require 'pathname'

begin
	require 'arborist'

	Loggability.level = :debug
	Loggability.format_with( :color )

rescue Exception => e
	$stderr.puts "Ack! Libraries failed to load: #{e.message}\n\t" +
		e.backtrace.join( "\n\t" )
end


