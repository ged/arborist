#!/usr/bin/env ruby

require 'cztop'

ENDPOINT = 'tcp://127.0.0.1:8733'

ctx = ZMQ::Context.new
sock = ctx.socket( :REP )
# sock.verbose = true
sock.bind( ENDPOINT )
sock.linger = 1

while request = sock.recv
	work = rand * 20.0
	puts "Got a request. Sleeping for %0.2fs" % [ work ]
	sleep( work )
	sock.send "HERE YOU GO %d: [%.5f].\n" % [ request, Time.now.to_f ]
end

