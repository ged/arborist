#!/usr/bin/env ruby

require 'rbczmq'

ENDPOINT = 'tcp://127.0.0.1:8733'

ctx = ZMQ::Context.new
sock = ctx.socket( :REQ )
# sock.verbose = true
sock.connect( ENDPOINT )

loop do
	pid = $$
	sock.send( pid.to_s )
	reply = sock.recv
	puts "Got: %s" % [ reply ]
end

