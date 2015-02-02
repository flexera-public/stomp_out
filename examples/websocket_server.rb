
# Example of a StompOut::Server subclass in a WebSocket environment
class WebSocketServer < StompOut::Server

  def initialize(options = {})
    @parent = options.delete(:parent)
    @subscriptions = {}
    @message_ids = {}
    super(options.merge(:name => self.class.name))
  end

  def send_data(data)
    @parent.send_data(data)
  end

  def on_connect(frame, login, passcode, host, session_id)
    true
  end

  def on_message(frame, destination, message, content_type)
    @parent.deliver_message(destination, message, content_type)
  end

  def on_subscribe(frame, id, destination, ack_setting)
    @subscriptions[id] = {:destination => destination, :ack_setting => ack_setting}
  end

  def on_unsubscribe(frame, id, destination)
    @subscriptions.delete(id)
  end

  def on_ack(frame, id)
    @parent.delete_message(@message_ids.delete(id))
  end

  def on_nack(frame, id)
    @message_ids.delete(id)
  end

  def on_error(frame, error)
    EM.next_tick { @parent.close_websocket }
  end

  def on_disconnect(frame, reason)
    EM.next_tick { @parent.close_websocket }
  end

  def deliver_messages(destination, messages)
    @subscriptions.each do |id, s|
      if s[:destination] == destination
        messages.each do |m|
          headers = {
            "subscription" => id,
            "destination" => destination,
            "message-id" => m[:id].to_s,
            "content-type" => m[:content_type] }
          message_id, ack_id = message(headers, m[:message])
          if s[:ack_setting] == "auto"
            @parent.delete_message(message_id)
          else
            @message_ids[ack_id] = message_id
          end
        end
      end
    end
  end
end

# Simple WebSocket Rack application using WebSocketServer
class WebSocketServerApp < Rack::WebSocket::Application

  @@servers = {}
  @@connections = {}
  @@connection_id = 0
  @@messages = Hash.new { |h, k| h[k] = [] }
  @@message_id = 0

  def initialize(options = {})
    super
  end

  def on_open(env)
    socket = env["async.connection"]
    @@connections[socket] = @@connection_id += 1
    puts "opened connection #{@@connection_id}"
    @@servers[socket] = WebSocketServer.new(:parent => self)
  end

  def on_close(env)
    socket = env["async.connection"]
    connection = @@connections.delete(socket)
    puts "closed connection #{connection}"
    @@servers.delete(socket)
  end

  def on_error(env, error)
    socket = env["async.connection"]
    connection = @@connections[socket]
    STDERR.puts "error on connection #{connection} (#{error})"
  end

  def on_message(env, message)
    socket = env["async.connection"]
    connection = @@connections[socket]
    puts "received #{message} on connection #{connection}"
    @@servers[socket].receive_data(JSON.load(message))
  end

  def send_data(data)
    data = JSON.dump(data)
    puts "sending #{data}"
    super(data)
  end

  def deliver_message(destination, message, content_type)
    @@messages[destination] << {:id => (@@message_id += 1).to_s, :message => message, :content_type => content_type}
    @@servers.each_value { |s| s.deliver_messages(destination, @@messages[destination]) }
  end

  def delete_message(id)
    @@messages.each_value { |ms| ms.reject! { |m| m[:id] == id } }
  end
end
