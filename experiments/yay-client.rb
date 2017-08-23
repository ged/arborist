#!/usr/bin/env ruby

require 'cztop'

# ENDPOINT = 'tcp://127.0.0.1:5000'
ENDPOINT = 'ipc:///tmp/arborist_api.sock'

ctx = ZMQ::Context.new
sock = ctx.socket( :REQ )
sock.verbose = true
sock.connect( ENDPOINT )

pid = $$
sock.send( pid.to_s )
reply = sock.recv
puts "Got: %s" % [ reply ]

