# -*- ruby -*-
#encoding: utf-8

require 'arborist/loader' unless defined?( Arborist::Loader )


# A loader for Arborist that knows how to load stuff from files on disk.
class Arborist::Loader::File < Arborist::Loader

	##
	# The glob pattern to use for searching for files
	FILE_PATTERN = '**/*.rb'


	### Create a new loader that will read nodes from the specified +directory+.
	def initialize( directory )
		Arborist.load_all
		@directory = directory
	end


	# The directory to load files from
	attr_reader :directory


	### Return an Enumerator
	def paths
		path = Pathname( self.directory )
		if path.directory?
			return Pathname.glob( directory + FILE_PATTERN ).each
		else
			return [ path ].each
		end
	end


	### Return an Enumerator that yields Arborist::Nodes loaded from the target
	### directory.
	def nodes
		return self.enumerator_for( Arborist::Node )
	end


	### Return an Enumerator that yields Arborist::Monitors loaded from the target
	### directory.
	def monitors
		return self.enumerator_for( Arborist::Monitor )
	end


	### Return an Enumerator that yields Arborist::Observers loaded from the target
	### directory.
	def observers
		return self.enumerator_for( Arborist::Observer )
	end


	### Return an Enumerator that will instantiate and yield instances of the specified
	### +arborist_class+ for each file path in the loader's directory.
	def enumerator_for( arborist_class )
		return Enumerator.new do |yielder|
			self.paths.each do |file|
				objects = arborist_class.load( file )
				objects.each do |object|
					object.source = "file://%s" % [ file.expand_path ]
					yielder.yield( object )
				end
			end
		end
	end

end # class Arborist::Loader::File
