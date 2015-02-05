# Example of a StompOut::Server subclass in a WebSocket environment
class WebSocketServer < StompOut::Server

  def initialize(options = {})
    options = options.dup
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
  @@server_id = 0
  @@messages = Hash.new { |h, k| h[k] = [] }
  @@message_id = 0

  def on_open(env)
    @server_id = (@@server_id += 1)
    puts "opened #{@server_id}"
    @@servers[@server_id] = WebSocketServer.new(:parent => self)
  end

  def on_close(env)
    puts "closed #{@server_id}"
    @@servers.delete(@server_id)
  end

  def on_error(env, error)
    STDERR.puts "error on connection #{@server_id} (#{error})"
  end

  def on_message(env, message)
    puts "STOMP <#{@server_id} #{message.inspect}"
    @@servers[@server_id].receive_data(message)
  end

  def send_data(data)
    puts "STOMP >#{@server_id} #{data.inspect}"
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
