#!/usr/bin/env ruby

require 'rubygems'
$:.unshift(File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib')))
require 'bundler/setup'
require 'eventmachine'
require 'faye/websocket'
require 'trollop'
require 'json'
require 'stomp_out'

# Example use of StompOut::Client with a WebSocket connection to a STOMP server
class WebSocketClient

  def self.run
    r = WebSocketClient.new
    options = r.parse_args
    r.start(options)
  end

  def start(options)
    @destination = options[:destination]
    @ack = options[:ack] || "auto"
    @message = options[:message]
    @receipts = {}

    ['INT', 'TERM'].each do |signal|
      trap(signal) do stop end
    end

    EM.run do
      @stomp = StompOut::Client.new(self, :host => options[:host], :receipt => options[:receipt], :auto_json => true)
      @ws = Faye::WebSocket::Client.new(options[:url])
      @ws.onerror = lambda { |e| puts "error #{e.message}"; stop }
      @ws.onclose = lambda { |e| puts "close #{e.code} #{e.reason}"; stop }
      @ws.onmessage = lambda { |e| puts "received: #{e.data}"; @stomp.receive_data(JSON.load(e.data)) }
      @stomp.connect
    end
  end

  def send_data(data)
    data = JSON.dump(data)
    puts "sending: #{data}"
    @ws.send(data)
  end

  def on_connected(frame, session_id, server_name)
    @connected = true
    puts "connected to #{server_name} for session #{session_id}"
    puts "subscribing to #{@destination} with ack #{@ack}"
    receipt_id = @stomp.subscribe(@destination, @ack, receipt = true)
    @receipts[receipt_id] = "subscribe to #{@destination} with ack #{@ack}" if receipt_id
    if @message
      receipt_id = @stomp.message(@destination, @message)
      @receipts[receipt_id] = "message to #{@destination}" if receipt_id
    end
  end

  def on_message(frame, destination, message, content_type, message_id, ack_id)
    puts "received #{content_type} message #{message_id} from #{destination} " +
         "with ack #{ack_id.inspect}: #{message.inspect}"
    if @ack != "auto"
      receipt_id = @stomp.ack(ack_id)
      @receipts[receipt_id] = "ack #{ack_id}" if receipt_id
    end
  end

  def on_receipt(frame, receipt_id)
    @subscribed = true if @receipts[receipt_id].to_s =~ /subscribe to/
    puts "received receipt #{receipt_id} for #{@receipts.delete(receipt_id).inspect}"
  end

  def on_error(frame, error, details, receipt_id)
    puts "error with receipt_id #{receipt_id.inspect}: #{error}" + (details ? "\n#{details}" : "")
    stop
  end

  def stop
    if EM.reactor_running?
      if @stomp && @connected
        @connected = false
        if @subscribed
          @subscribed = false
          puts "unsubscribing from #{@destination}"
          receipt_id = @stomp.unsubscribe(@destination)
          @receipts[receipt_id] = "unsubscribe from #{@destination}" if receipt_id
        end
        receipt_id = @stomp.disconnect
        @receipts[receipt_id] = "disconnect" if receipt_id
      end

      # Give server chance to respond before disconnect
      EM.add_timer(0.25) do
        @ws.close if @ws
        EM.add_timer(0.25) { EM.stop }
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
      puts(version)
      exit 0
    rescue Trollop::HelpNeeded
      puts("Usage: websocket_client --url <s> --destination <s> [--host <s> --ack <s> --receipt --message <s>]")
      exit 0
    rescue Trollop::CommandlineError => e
      STDERR.puts e.message + "\nUse --help for additional information"
      exit 1
    end
  end

end # WebSocketClient

WebSocketClient.run
