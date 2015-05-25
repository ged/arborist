#!/usr/bin/env ruby

require 'arborist'


Arborist.load_config( ARGV.first )
manager = Arborist::Manager.new
manager.run


