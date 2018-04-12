#!/usr/bin/env rake

require 'pathname'
require 'rake/clean'

begin
	require 'hoe'
rescue LoadError
	abort "This Rakefile requires hoe (gem install hoe)"
end

GEMSPEC = 'arborist.gemspec'

BASEDIR = Pathname( __FILE__ ).dirname
LIBDIR = BASEDIR + 'lib'
NODE_STATE_GRAPH = BASEDIR + 'node-state-machine.dot'


Hoe.plugin :mercurial
Hoe.plugin :signing
Hoe.plugin :deveiate

Hoe.plugins.delete :rubyforge


hoespec = Hoe.spec 'arborist' do |spec|
	spec.readme_file = 'README.md'
	spec.history_file = 'History.md'
	spec.extra_rdoc_files = FileList[ '*.rdoc', '*.md' ]
	spec.license 'BSD-3-Clause'
	spec.urls = {
		home:   'http://deveiate.org/projects/arborist',
		code:   'http://bitbucket.org/ged/arborist',
		docs:   'http://deveiate.org/code/arborist',
		github: 'http://github.com/ged/arborist',
	}

	spec.developer 'Michael Granger', 'ged@FaerieMUD.org'
	spec.developer 'Mahlon E. Smith', 'mahlon@martini.nu'

	spec.dependency 'schedulability', '~> 0.1'
	spec.dependency 'loggability', '~> 0.12'
	spec.dependency 'configurability', '~> 3.0'
	spec.dependency 'pluggability', '~> 0.4'
	spec.dependency 'state_machines', '~> 0.5'
	spec.dependency 'msgpack', '~> 1.0'
	spec.dependency 'cztop', '~> 0.11'
	spec.dependency 'cztop-reactor', '~> 0.3'
	spec.dependency 'gli', '~> 2.3'
	spec.dependency 'tty', '~> 0.7'
	spec.dependency 'tty-tree', '~> 0.1'
	spec.dependency 'pry', '~> 0.11'

	spec.dependency 'rspec', '~> 3.2', :developer
	spec.dependency 'rspec-wait', '~> 0.0', :developer
	spec.dependency 'simplecov', '~> 0.9', :developer
	spec.dependency 'timecop', '~> 0.7', :developer
	spec.dependency 'rdoc', '~> 5.1', :developer
	spec.dependency 'rdoc', '~> 5.1', :developer
	spec.dependency 'state_machines-graphviz', '~> 0.0', :developer

	spec.require_ruby_version( '>=2.3.1' )
	spec.hg_sign_tags = true if spec.respond_to?( :hg_sign_tags= )

	spec.rdoc_locations << "deveiate:/usr/local/www/public/code/#{remote_rdoc_dir}"
end


ENV['VERSION'] ||= hoespec.spec.version.to_s

# Run the tests before checking in
task 'hg:precheckin' => [ :check_history, :check_manifest, :gemspec, :spec ]

# Rebuild the ChangeLog immediately before release
task :prerelease => 'ChangeLog'
CLOBBER.include( 'ChangeLog' )

desc "Build a coverage report"
task :coverage do
	ENV["COVERAGE"] = 'yes'
	Rake::Task[:spec].invoke
end


# Use the fivefish formatter for docs generated from development checkout
if File.directory?( '.hg' )
	require 'rdoc/task'

	Rake::Task[ 'docs' ].clear
	RDoc::Task.new( 'docs' ) do |rdoc|
	    rdoc.main = "README.md"
	    rdoc.rdoc_files.include( "*.rdoc", "*.md", "ChangeLog", "lib/**/*.rb" )
	    rdoc.generator = :fivefish
		rdoc.title = 'Arborist'
	    rdoc.rdoc_dir = 'doc'
	end
end

file 'Manifest.txt'

task :gemspec => [ 'ChangeLog', __FILE__, 'Manifest.txt', GEMSPEC ]
file GEMSPEC => __FILE__ do |task|
	spec = $hoespec.spec
	spec.files.delete( '.gemtest' )
	spec.files.delete( 'LICENSE' )
	spec.signing_key = nil
	spec.version = "#{spec.version.bump}.0.pre#{Time.now.strftime("%Y%m%d%H%M%S")}"
	#spec.cert_chain = [ 'certs/ged.pem' ]
	File.open( task.name, 'w' ) do |fh|
		fh.write( spec.to_ruby )
	end
end
CLOBBER.include( GEMSPEC )

task :default => :gemspec


file NODE_STATE_GRAPH

desc "Generate a graph of the node status state machine."
task NODE_STATE_GRAPH do |task|
	$LOAD_PATH.unshift( LIBDIR.to_s )

	require 'state_machines'
	require 'state_machines/graphviz'
	require 'arborist/node'

	state_machine = Arborist::Node.state_machine
	name = File.basename( NODE_STATE_GRAPH, '.dot' )
	puts "Writing status state machine diagram to #{NODE_STATE_GRAPH}"
	graph = state_machine.draw( path: BASEDIR.to_s, name: name, format: 'dot' )
	# graph.output
end

CLEAN.include( NODE_STATE_GRAPH.to_s )


task :diagrams => [ NODE_STATE_GRAPH ]

