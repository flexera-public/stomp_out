require 'rubygems'
$:.unshift(File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib')))
require 'bundler/setup'
require 'rack'
require 'rack/server'
require 'eventmachine'
require 'rack/websocket'
require 'stomp_out'
require './websocket_server'

map '/' do
  run WebSocketServerApp.new
end
