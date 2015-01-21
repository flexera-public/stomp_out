# -*-ruby-*-
require 'rubygems'
require 'rake'
require 'right_develop'
require 'spec/rake/spectask'
require 'rubygems/package_task'
require 'rake/clean'

task :default => [:spec]

desc "Run unit tests"
Spec::Rake::SpecTask.new do |t|
  t.spec_files = Dir['**/*_spec.rb']
  t.spec_opts = lambda do
    IO.readlines(File.join(File.dirname(__FILE__), 'spec', 'spec.opts')).map {|l| l.chomp.split " "}.flatten
  end
end

require 'jeweler'
Jeweler::Tasks.new do |gem|
  # gem is a Gem::Specification; see http://docs.rubygems.org/read/chapter/20 for more options
  gem.name = "stomp_out"
  gem.homepage = "https://github.com/rightscale/stomp_out"
  gem.license = "MIT"
  gem.summary = %Q{Client and server for STOMP protocol that operate outboard of separately supplied network connection.}
  gem.description = %Q{This implementation of STOMP is aimed at environments where a network connection, such as a WebSocket or TCP socket, is created and then raw data from that connection is passed to/from the STOMP client or server messaging layer provided by this gem.}
  gem.email = "support@rightscale.com"
  gem.authors = ["Lee Kirchhoff"]
  gem.files.exclude "Gemfile*"
  gem.files.exclude "spec/**/*"
end
Jeweler::RubygemsDotOrgTasks.new

CLEAN.include("pkg")

RightDevelop::CI::RakeTask.new
