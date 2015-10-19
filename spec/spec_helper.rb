unless RUBY_VERSION < "1.9"
  require 'coveralls'
  Coveralls.wear!
end
require 'rubygems'
require 'bundler/setup'
require 'rspec'
require 'flexmock'
require 'eventmachine'

$:.unshift(File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib')))
require 'stomp_out'

Spec::Runner.configure do |config|
  config.mock_with :flexmock
end
