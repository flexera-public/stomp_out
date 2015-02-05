#!/usr/bin/env ruby

require 'rubygems'
$:.unshift(File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib')))
require 'bundler/setup'
require 'eventmachine'
require 'faye/websocket'
require 'trollop'
require 'json'
require 'stomp_out'

# Example of a StompOut::Client subclass in a WebSocket environment
class WebSocketClient < StompOut::Client

  def initialize(options = {})
    options = options.dup
    @parent = options.delete(:parent)
    @destination = options.delete(:destination)
    @ack = options.delete(:ack) || "auto"
    @message = options.delete(:message)
    @receipts = {}

    super(options)
  end

  def send_data(data)
    @parent.send_data(data)
  end

  def on_connected(frame, session_id, server_name)
    puts "connected to #{server_name.inspect} for session #{session_id.inspect}"
    if @message
      receipt_id = message(@destination, @message)
      @receipts[receipt_id] = "message to #{@destination.inspect}" if receipt_id
      close
    else
      puts "subscribe #{@destination.inspect} with ack #{@ack.inspect}"
      receipt_id = subscribe(@destination, @ack, receipt = true)
      @receipts[receipt_id] = "subscribe #{@destination.inspect} with ack #{@ack.inspect}" if receipt_id
    end
  end

  def on_message(frame, destination, message, content_type, message_id, ack_id)
    puts "message #{message_id.inspect} of type #{content_type.inspect} from #{destination.inspect} " +
         "with ack #{ack_id.inspect}: #{message.inspect}"
    if @ack != "auto"
      receipt_id = ack(ack_id)
      @receipts[receipt_id] = "ack #{ack_id}" if receipt_id
    end
  end

  def on_receipt(frame, receipt_id)
    @subscribed = true if @receipts[receipt_id].to_s =~ /subscribe to/
    puts "receipt #{receipt_id.inspect} for #{@receipts.delete(receipt_id).inspect}"
  end

  def on_error(frame, error, details, receipt_id)
    receipt = receipt_id ? " with receipt #{receipt_id.inspect}" : nil
    puts "error#{receipt}: #{error}" + (details ? "\n#{details}" : "")
    close
  end

  def close
    if connected?
      if @subscribed
        @subscribed = false
        puts "unsubscribe #{@destination.inspect}"
        receipt_id = unsubscribe(@destination)
        @receipts[receipt_id] = "unsubscribe #{@destination.inspect}" if receipt_id
      end
      receipt_id = disconnect
      @receipts[receipt_id] = "disconnect" if receipt_id
      @parent.stop
    end
  end
end

# Simple application using WebSocketClient
class WebSocketClientApp

  def self.run
    r = WebSocketClientApp.new
    options = r.parse_args
    r.start(options)
  end

  def start(options)
    ['INT', 'TERM'].each do |signal|
      trap(signal) do EM.stop if EM.reactor_running? end
    end

    EM.run do
      @client = WebSocketClient.new(options.merge(:parent => self, :name => self.class.name, :auto_json => true))
      @websocket = Faye::WebSocket::Client.new(options[:url])
      @websocket.onerror = lambda { |e| puts "error #{e.message.inspect}"; stop }
      @websocket.onclose = lambda { |c| puts "close #{c.code} #{c.reason}"; stop }
      @websocket.onmessage = lambda { |m| puts "STOMP < #{m.data.inspect}"; @client.receive_data(m.data) }
      @client.connect
    end
  end

  def send_data(data)
    puts "STOMP > #{data.inspect}"
    @websocket.send(data)
  end

  def stop
    if EM.reactor_running?
      @client.close if @client

      EM.next_tick do
        @websocket.close if @websocket
        EM.next_tick { EM.stop }
      end
    end
  end

  def parse_args
    options = {}

    parser = Trollop::Parser.new do
      opt :url, "server WebSocket URL", :default => nil, :type => String, :short => "-u", :required => true
      opt :destination, "messaging destination", :default => nil, :type => String, :short => "-d", :required => true
      opt :host, "server virtual host name", :default => nil, :type => String, :short => "-h"
      opt :ack, "auto, client, or client-individual acks", :default => nil, :type => String, :short => "-a"
      opt :receipt, "enable receipts", :default => nil, :short => "-r"
      opt :message, "send message to destination", :default => nil, :type => String, :short => "-m"
      version ""
    end

    parse do
      options.merge!(parser.parse)
    end
  end

  def parse
    begin
      yield
    rescue Trollop::VersionNeeded
      puts version
      exit 0
    rescue Trollop::HelpNeeded
      puts "Usage: websocket_client --url <s> --destination <s> [--host <s> --ack <s> --receipt --message <s>]"
      exit 0
    rescue Trollop::CommandlineError => e
      STDERR.puts e.message + "\nUse --help for additional information"
      exit 1
    end
  end
end

WebSocketClientApp.run
