#!/usr/bin/ruby -*- ruby -*-

$LOAD_PATH.unshift( 'lib' )

require 'configurability'
require 'loggability'
require 'pathname'

begin
	require 'arborist'

	Loggability.level = :debug
	Loggability.format_with( :color )

	Arborist.load_all

rescue Exception => e
	$stderr.puts "Ack! Libraries failed to load: #{e.message}\n\t" +
		e.backtrace.join( "\n\t" )
end


