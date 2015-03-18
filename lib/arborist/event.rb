# -*- ruby -*-
#encoding: utf-8

require 'pluggability'

require 'arborist' unless defined?( Arborist )


# The base event type for events in an Arborist tree.
class Arborist::Event
	extend Pluggability


	# The prefixes to try when requiring plugins of this type
	plugin_prefixes 'arborist/event'


end # class Arborist::Event
