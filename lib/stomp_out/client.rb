# Copyright (c) 2015 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module StompOut

  # Abstract base class for STOMP client for use with an existing server connection, such
  # as a WebSocket. Derived classes are responsible for supplying the following functions:
  #   send_data(data) - send data over connection
  #   on_connected(frame, session_id, server_name) - handle notification that now connected
  #   on_message(frame, destination, message, content_type, message_id, ack_id) - handle message
  #     received from server
  #   on_receipt(frame, receipt_id) - handle notification that a request was successfully
  #     handled by server
  #   on_error(frame, message, details, receipt_id) - handle notification from server
  #     that a request failed and that the connection should be closed
  #
  class Client

    SUPPORTED_VERSIONS = ["1.0", "1.1", "1.2"]

    ACK_SETTINGS = {
      "1.0" => ["auto", "client"],
      "1.1" => ["auto", "client", "client-individual"],
      "1.2" => ["auto", "client", "client-individual"]
    }

    SERVER_COMMANDS = [:connected, :message, :receipt, :error]

    MIN_SEND_HEARTBEAT = 5000

    # [String] version of STOMP chosen for session
    attr_reader :version

    # [String] session_id assigned to session
    attr_reader :session_id

    # [String] name assigned to server
    attr_reader :server_name

    # [String] host to which client is connecting
    attr_reader :host

    # [Heartbeat] heartbeat generator and monitor
    attr_reader :heartbeat

    # Create STOMP client
    #
    # @option options [String] :host to which client wishes to connect; if not using virtual hosts,
    #   recommended setting is the host name that the socket in use was connected against,
    #   or any name of client's choosing; defaults to "stomp"
    # @option options [Boolean] :receipt enabled for all requests except connect; disabled
    #   by default but can still enable on individual requests
    # @option options [Boolean] :auto_json encode/decode "application/json" content-type
    # @option options [Integer] :min_send_interval in msec that this client can guarantee;
    #   defaults to MIN_SEND_HEARTBEAT
    def initialize(options = {})
      @options = options
      @host = @options[:host] || "stomp"
      @parser = StompOut::Parser.new
      @ack_id = 0
      @message_ids = {} # ack ID is key
      @subscribe_id = 0
      @subscribes = {} # destination is key
      @transaction_id = 0
      @transaction_ids = []
      @receipt = options[:receipt]
      @receipt_id = 0
      @receipted_frames = {} # receipt-id is key
      @connected = false
    end

    # List active subscriptions
    #
    # @return [Array<String>] subscription destinations
    def subscriptions
      @subscribes.keys
    end

    # List active transactions
    #
    # @return [Array<String>] transaction IDs
    def transactions
      @transaction_ids
    end

    # Determine whether connected to STOMP server
    #
    # @return [Boolean] true if connected, otherwise false
    def connected?
      !!@connected
    end

    # Report to client that an error was encountered locally
    # Not intended for use by end user of this class
    #
    # @param [Exception, String] error being reported
    #
    # @return [TrueClass] always true
    def report_error(error)
      details = ""
      if error.is_a?(ProtocolError) || error.is_a?(ApplicationError)
        message = error.message
      elsif error.is_a?(Exception)
        message = "#{error.class}: #{error.message}"
        details = error.backtrace.join("\n") if error.respond_to?(:backtrace)
      else
        message = error.to_s
      end
      frame = Frame.new("ERROR", {"message" => message}, details)
      on_error(frame, message, details, receipt_id = nil)
      true
    end

    # Process data received over connection from server
    #
    # @param [String] data to be processed
    #
    # @return [TrueClass] always true
    def receive_data(data)
      @parser << data
      process_frames
      @heartbeat.received_data if @heartbeat
      true
    rescue StandardError => e
      report_error(e)
    end

    ##################################
    ## STOMP client subclass functions
    ##################################

    # Send data over connection to server
    #
    # @param [String] data that is STOMP encoded
    #
    # @return [TrueClass] always true
    def send_data(data)
      raise "Not implemented"
    end

    # Handle notification that now connected to server
    #
    # @param [Frame] frame received from server
    # @param [String] session_id uniquely identifying the given STOMP session
    # @param [String, NilClass] server_name in form "<name>/<version>" with
    #   "/<version>" being optional; nil if not provided by server
    #
    # @return [TrueClass] always true
    def on_connected(frame, session_id, server_name)
      raise "Not implemented"
    end

    # Handle message received from server
    #
    # @param [Frame] frame received from server
    # @param [String] destination to which the message was sent
    # @param [Object] message body; if content_type is "application/json"
    #   and :auto_json client option specified the message is JSON decoded
    # @param [String] content_type of message in MIME terms, e.g., "text/plain"
    # @param [String] message_id uniquely identifying message
    # @param [String, NilClass] ack_id to be used when acknowledging message
    #   to server if acknowledgement enabled
    #
    # @return [TrueClass] always true
    def on_message(frame, destination, message, content_type, message_id, ack_id)
      raise "Not implemented"
    end

    # Handle notification that a request was successfully handled by server
    #
    # @param [Frame] frame received from server
    # @param [String] receipt_id identifying request completed (client request
    #   functions optionally return a receipt_id)
    #
    # @return [TrueClass] always true
    def on_receipt(frame, receipt_id)
      raise "Not implemented"
    end

    # Handle notification from server that a request failed and that the connection
    # should be closed
    #
    # @param [Frame] frame received from server
    # @param [String] error message
    # @param [String, NilClass] details about the error, e.g., the frame that failed
    # @param [String, NilClass] receipt_id identifying request that failed (Client
    #   functions optionally return a receipt_id)
    #
    # @return [TrueClass] always true
    def on_error(frame, error, details, receipt_id)
      raise "Not implemented"
    end

    ########################
    ## STOMP client commands
    ########################

    # Connect to server
    #
    # @param [Integer, NilClass] heartbeat rate in milliseconds that is desired;
    #   defaults to no heartbeat; not usable unless eventmachine gem available
    # @param [String, NilClass] login name for authentication with server; defaults
    #   to no authentication, although this may not be acceptable to server
    # @param [String, NilClass] passcode for authentication
    # @param [Hash, NilClass] headers that are application specific
    #
    # @return [TrueClass] always true
    #
    # @raise [ProtocolError] already connected
    # @raise [ApplicationError] eventmachine not available
    def connect(heartbeat = nil, login = nil, passcode = nil, headers = nil)
      raise ProtocolError, "Already connected" if @connected
      headers ||= {}
      headers["accept-version"] = SUPPORTED_VERSIONS.join(",")
      headers["host"] = @host
      if heartbeat
        raise ApplicationError.new("Heartbeat not usable without eventmachine") unless Heartbeat.usable?
        headers["heart-beat"] = "#{@options[:min_send_interval] || MIN_SEND_HEARTBEAT},#{heartbeat}"
      end
      if login
        headers["login"] = login
        headers["passcode"] = passcode
      end
      send_frame("CONNECT", headers)
      true
    end

    # Send message to given destination
    #
    # @param [String] destination for message
    # @param [String] message being sent
    # @param [String, NilClass] content_type of message body in MIME format;
    #   optionally JSON-encodes body automatically if "application/json";
    #   defaults to "plain/text"
    # @param [Boolean, NilClass] receipt enabled (or'd with global setting)
    # @param [String, NilClass] transaction_id for transaction into which this command
    #   is to be included; defaults to no transaction
    # @param [Hash] headers that are application specific, e.g., "message-id"
    #
    # @return [String, NilClass] receipt ID if enabled, otherwise nil
    #
    # @raise [ProtocolError] not connected
    def message(destination, message, content_type = nil, receipt = nil, transaction_id = nil, headers = nil)
      raise ProtocolError.new("Not connected") unless @connected
      headers ||= {}
      headers["destination"] = destination
      frame = send_frame("SEND", headers, message, content_type, receipt, transaction_id)
      frame.headers["receipt"]
    end

    # Register to listen to a given destination
    #
    # @param [String] destination of interest
    # @param [String, NilClass] ack setting: "auto", "client", or "client-individual";
    #   defaults to "auto"
    # @param [Boolean, NilClass] receipt enabled (or'd with global setting)
    # @param [Hash, NilClass] headers that are application specific
    #
    # @return [String, NilClass] receipt ID if enabled, otherwise nil
    #
    # @raise [ProtocolError] not connected, invalid ack setting
    # @raise [ApplicationError] duplicate subscription
    def subscribe(destination, ack = nil, receipt = nil, headers = nil)
      raise ProtocolError.new("Not connected") unless @connected
      raise ApplicationError.new("Already subscribed to '#{destination}'") if @subscribes[destination]
      raise ProtocolError.new("Invalid 'ack' setting") if ack && !ACK_SETTINGS[@version].include?(ack)
      @subscribes[destination] = {:id => (@subscribe_id += 1).to_s, :ack => ack}
      headers ||= {}
      headers["destination"] = destination
      headers["id"] = @subscribe_id.to_s
      headers["ack"] = ack if ack
      frame = send_frame("SUBSCRIBE", headers, body = nil, content_type = nil, receipt)
      frame.headers["receipt"]
    end

    # Remove an existing subscription
    #
    # @param [String] destination no longer of interest
    #
    # @return [String, NilClass] receipt ID if enabled, otherwise nil
    # @param [Boolean, NilClass] receipt enabled (or'd with global setting)
    # @param [Hash, NilClass] headers that are application specific
    #
    # @raise [ProtocolError] not connected
    # @raise [ApplicationError] subscription not found
    def unsubscribe(destination, receipt = nil, headers = nil)
      raise ProtocolError.new("Not connected") unless @connected
      subscribe = @subscribes.delete(destination)
      raise ApplicationError.new("Subscription to '#{destination}' not found") if subscribe.nil?
      headers ||= {}
      headers["id"] = subscribe[:id]
      headers["destination"] = destination if @version == "1.0"
      frame = send_frame("UNSUBSCRIBE", headers, body = nil, content_type = nil, receipt)
      frame.headers["receipt"]
    end

    # Acknowledge consumption of a message from a subscription
    #
    # @param [String] ack_id identifying message being acknowledged
    # @param [Boolean, NilClass] receipt enabled (or'd with global setting)
    # @param [String, NilClass] transaction_id for transaction into which this command
    #   is to be included; defaults to no transaction
    # @param [Hash, NilClass] headers that are application specific
    #
    # @return [String, NilClass] receipt ID if enabled, otherwise nil
    #
    # @raise [ProtocolError] not connected
    # @raise [ApplicationError] message for ack not found
    def ack(ack_id, receipt = nil, transaction_id = nil, headers = nil)
      raise ProtocolError.new("Not connected") unless @connected
      message_id = @message_ids.delete(ack_id)
      headers ||= {}
      if @version == "1.0"
        raise ApplicationError.new("No message was received with ack #{ack_id}") if message_id.nil?
        headers["message-id"] = message_id
        frame = send_frame("ACK", headers, body = nil, content_type = nil, receipt, transaction_id)
      else
        headers["id"] = ack_id.to_s
        frame = send_frame("ACK", headers, body = nil, content_type = nil, receipt, transaction_id)
      end
      frame.headers["receipt"]
    end

    # Tell the server that a message was not consumed
    #
    # @param [String] ack_id identifying message being negatively acknowledged
    # @param [Boolean, NilClass] receipt enabled (or'd with global setting)
    # @param [String, NilClass] transaction_id for transaction into which this command
    #   is to be included; defaults to no transaction
    # @param [Hash, NilClass] headers that are application specific
    #
    # @return [String, NilClass] receipt ID if enabled, otherwise nil
    #
    # @raise [ProtocolError] nack not supported, not connected
    def nack(ack_id, receipt = nil, transaction_id = nil, headers = nil)
      raise ProtocolError.new("Command 'nack' not supported") if @version == "1.0"
      raise ProtocolError.new("Not connected") unless @connected
      @message_ids.delete(ack_id)
      headers ||= {}
      headers["id"] = ack_id.to_s
      frame = send_frame("NACK", headers, body = nil, content_type = nil, receipt, transaction_id)
      frame.headers["receipt"]
    end

    # Start a transaction
    #
    # @param [Boolean, NilClass] receipt enabled (or'd with global setting)
    #
    # @return [Array<String>] transaction ID and receipt ID if receipt enabled
    # @param [Hash, NilClass] headers that are application specific
    #
    # @raise [ProtocolError] not connected
    def begin(receipt = nil, headers = nil)
      raise ProtocolError.new("Not connected") unless @connected
      id = (@transaction_id += 1).to_s
      headers ||= {}
      headers["transaction"] = id.to_s
      frame = send_frame("BEGIN", headers, body = nil, content_type = nil, receipt)
      @transaction_ids << id
      [id, frame.headers["receipt"]]
    end

    # Commit a transaction
    #
    # @param [String] transaction_id uniquely identifying transaction
    # @param [Boolean, NilClass] receipt enabled (or'd with global setting)
    # @param [Hash, NilClass] headers that are application specific
    #
    # @return [String, NilClass] receipt ID if enabled, otherwise nil
    #
    # @raise [ProtocolError] not connected
    # @raise [ApplicationError] transaction not found
    def commit(id, receipt = nil, headers = nil)
      raise ProtocolError.new("Not connected") unless @connected
      raise ApplicationError.new("Transaction #{id} not found") unless @transaction_ids.delete(id.to_s)
      headers ||= {}
      headers["transaction"] = id.to_s
      frame = send_frame("COMMIT", headers, body = nil, content_type = nil, receipt)
      frame.headers["receipt"]
    end

    # Roll back a transaction
    #
    # @param [String] id uniquely identifying transaction
    # @param [Boolean, NilClass] receipt enabled (or'd with global setting)
    # @param [Hash, NilClass] headers that are application specific
    #
    # @return [String, NilClass] receipt ID if enabled, otherwise nil
    #
    # @raise [ProtocolError] not connected
    # @raise [ApplicationError] transaction not found
    def abort(id, receipt = nil, headers = nil)
      raise ProtocolError.new("Not connected") unless @connected
      raise ApplicationError.new("Transaction #{id} not found") unless @transaction_ids.delete(id.to_s)
      headers ||= {}
      headers["transaction"] = id.to_s
      frame = send_frame("ABORT", headers, body = nil, content_type = nil, receipt)
      frame.headers["receipt"]
    end

    # Disconnect from the server
    # Client is expected to close its connection after calling this function
    # If receipt is requested, it may not be received before frame is reset
    #
    # @param [Boolean, NilClass] receipt enabled (or'd with global setting)
    # @param [Hash, NilClass] headers that are application specific
    #
    # @return [String, NilClass] receipt ID if enabled and connected, otherwise nil
    #
    # @raise [ProtocolError] not connected
    def disconnect(receipt = nil, headers = nil)
      raise ProtocolError.new("Not connected") unless @connected
      frame = send_frame("DISCONNECT", headers, body = nil, content_type = nil, receipt)
      @heartbeat.stop if @heartbeat
      @connected = false
      frame.headers["receipt"]
    end

    protected

    ########################
    ## STOMP Server Commands
    ########################

    # Handle notification from server that now connected at STOMP protocol level
    #
    # @param [Frame] frame received from server
    # @param [String, NilClass] body for frame after optional decoding
    #
    # @return [TrueClass] always true
    def receive_connected(frame, body)
      @version = frame.headers["version"] || "1.0"
      @session_id = frame.headers["session"]
      @server_name = frame.headers["server"]
      if frame.headers["heart-beat"]
        @heartbeat = Heartbeat.new(self, frame.headers["heart-beat"])
        @heartbeat.start
      end
      @connected = true
      on_connected(frame, @session_id, @server_name)
      true
    end

    # Handle message from server
    # Attempt to decode body if not text
    #
    # @param [Frame] frame received from server
    # @param [String, NilClass] body for frame after optional decoding
    #
    # @return [TrueClass] always true
    #
    # @raise [ApplicationError] subscription not found, subscription does not
    #   match destination, duplicate ack ID
    def receive_message(frame, body)
      required = {"destination" => [], "message-id" => [], "subscription" => ["1.0"]}
      destination, message_id, subscribe_id = frame.require(@version, required)
      if (subscribe = @subscribes[destination])
        if subscribe[:id] != subscribe_id && @version != "1.0"
          raise ApplicationError.new("Subscription does not match destination '#{destination}'", frame)
        end
        ack_id = nil
        if subscribe[:ack] != "auto"
          # Create ack ID if there is none so that user of this class can always rely
          # on its use for ack/nack and then correspondingly track message IDs so that
          # convert back to ack ID when needed
          ack_id = frame.require(@version, "ack" => ["1.0", "1.1"])
          ack_id ||= (@ack_id += 1).to_s
          if (message_id2 = @message_ids[ack_id])
            raise ApplicationError.new("Duplicate ack #{ack_id} for messages #{message_id2} and #{message_id}", frame)
          end
          @message_ids[ack_id] = message_id
        end
      else
        raise ApplicationError.new("Subscription to '#{destination}' not found", frame)
      end
      content_type = frame.headers["content-type"] || "text/plain"
      on_message(frame, destination, body, content_type, message_id, ack_id)
      true
    end

    # Handle receipt acknowledgement from server for frame sent earlier
    #
    # @param [Frame] frame received from server
    # @param [String, NilClass] body for frame after optional decoding
    #
    # @return [TrueClass] always true
    #
    # @raise [ProtocolError] missing header
    # @raise [ApplicationError] request for receipt not found
    def receive_receipt(frame, body)
      id = frame.require(@version, "receipt-id" => [])
      raise ApplicationError.new("Request not found matching receipt #{id}") if @receipted_frames.delete(id).nil?
      on_receipt(frame, id)
    end

    # Handle error reported by server
    #
    # @param [Frame] frame received from server
    # @param [String, NilClass] body for frame after optional decoding
    #
    # @return [TrueClass] always true
    def receive_error(frame, body)
      on_error(frame, frame.headers["message"], body, frame.headers["receipt-id"])
      true
    end

    ##########################
    ## STOMP Support Functions
    ##########################

    # Process all complete frames that have been received
    #
    # @return [TrueClass] always true
    def process_frames
      while (frame = @parser.next) do process_frame(frame) end
      true
    end

    # Process frame received from server
    # Optionally JSON-decode body if "content-type" is "application/json"
    #
    # @param [Frame] frame received; body updated on return if is decoded
    #
    # @return [TrueClass] always true
    #
    # @raise [ProtocolError] unhandled frame
    def process_frame(frame)
      command = frame.command.downcase.to_sym
      raise ProtocolError.new("Unhandled frame: #{frame.command}", frame) unless SERVER_COMMANDS.include?(command)
      if (body = frame.body) && !body.empty? && frame.headers["content-type"] == "application/json" && @options[:auto_json]
        body = JSON.load(body)
      end
      send(("receive_" + command.to_s).to_sym, frame, body)
    end

    # Send frame to server
    # Optionally JSON-encode body if "content-type" is "application/json"
    #
    # @param [String] command name
    # @param [Hash, NilClass] headers for frame; others added if there is a body
    # @param [String, NilClass] body of message
    # @param [String, NilClass] content_type per MIME; defaults to "text/plain"
    # @param [Boolean, NilClass] receipt enabled (or'd with global setting)
    # @param [String, NilClass] transaction_id uniquely identifying transaction
    #
    # @return [Frame] frame sent
    #
    # @raise [ApplicationError] transaction not found
    def send_frame(command, headers = nil, body = nil, content_type = nil, receipt = nil, transaction_id = nil)
      headers ||= {}
      if body && !body.empty?
        headers["content-type"] = content_type || "text/plain"
        body = JSON.dump(body) if content_type == "application/json" && @options[:auto_json]
        headers["content-length"] = body.size.to_s
      else
        body = ""
      end
      if transaction_id
        transaction_id = transaction_id.to_s
        raise ApplicationError.new("Transaction not found") unless @transaction_ids.index(transaction_id)
        headers["transaction"] = transaction_id
      end
      frame = StompOut::Frame.new(command, headers, body)
      if (receipt || @receipt) && command != "CONNECT"
        receipt_id = frame.headers["receipt"] = (@receipt_id += 1).to_s
        @receipted_frames[receipt_id] = frame
      end
      send_data(frame.to_s)
      @heartbeat.sent_data if @heartbeat
      frame
    end

  end # Client

end # StompOut