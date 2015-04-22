#!/usr/bin/env ruby

require 'rbczmq'

ENDPOINT = 'tcp://127.0.0.1:8733'

ctx = ZMQ::Context.new
sock = ctx.socket( :REP )
# sock.verbose = true
sock.bind( ENDPOINT )
sock.linger = 1

while request = sock.recv
	sock.send "HERE YOU GO %d: [%.5f].\n" % [ request, Time.now.to_f ]
end

