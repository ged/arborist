# -*- ruby -*-
#encoding: utf-8

require 'pluggability'
require 'arborist' unless defined?( Arborist )


# Abstract base class for Arborist loader strategies
class Arborist::Loader
	extend Loggability,
	       Pluggability


	# Loggability API -- use the Arborist logger
	log_to :arborist

	# Pluggability API -- search for loaders under the specified path
	plugin_prefixes 'arborist/loader'


	### Return an Enumerator that yields Arborist::Nodes loaded from the target
	### directory.
	def nodes
		raise NotImplementedError, "%p needs to implement #nodes"
	end


	### Return an Enumerator that yields Arborist::Monitors loaded from the target
	### directory.
	def monitors
		raise NotImplementedError, "%p needs to implement #monitors"
	end


	### Return an Enumerator that yields Arborist::Observers loaded from the target
	### directory.
	def observers
		raise NotImplementedError, "%p needs to implement #observers"
	end


end # class Arborist::Loader

