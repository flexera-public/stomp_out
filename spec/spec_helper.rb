require 'rubygems'
$:.unshift(File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib')))
require 'bundler/setup'
require 'spec'
require 'flexmock'
require 'eventmachine'
require 'stomp_out'

Spec::Runner.configure do |config|
  config.mock_with :flexmock
end
