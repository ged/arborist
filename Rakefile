#!/usr/bin/env rake

begin
	require 'hoe'
rescue LoadError
	abort "This Rakefile requires hoe (gem install hoe)"
end

GEMSPEC = 'arborist.gemspec'


Hoe.plugin :mercurial
Hoe.plugin :signing
Hoe.plugin :deveiate

Hoe.plugins.delete :rubyforge
Hoe.plugins.delete :gemcutter

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
	spec.dependency 'loggability', '~> 0.11'
	spec.dependency 'configurability', '~> 2.2'
	spec.dependency 'pluggability', '~> 0.4'
	spec.dependency 'state_machines', '~> 0.2'
	spec.dependency 'msgpack', '~> 0.6'
	spec.dependency 'rbczmq', '~> 1.7'

	spec.dependency 'rspec', '~> 3.2', :developer
	spec.dependency 'simplecov', '~> 0.9', :developer
	spec.dependency 'timecop', '~> 0.7', :developer

	spec.require_ruby_version( '>=2.2.0' )
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

task :gemspec => GEMSPEC
file GEMSPEC => __FILE__ do |task|
	spec = $hoespec.spec
	spec.files.delete( '.gemtest' )
	spec.signing_key = nil
	spec.version = "#{spec.version}.pre#{Time.now.strftime("%Y%m%d%H%M%S")}"
	File.open( task.name, 'w' ) do |fh|
		fh.write( spec.to_ruby )
	end
end

task :default => :gemspec

