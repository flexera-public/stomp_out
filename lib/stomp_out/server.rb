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

require 'simple_uuid'

module StompOut

  # Abstract base class for STOMP server for use with an existing client connection, such
  # as a WebSocket. Derived classes are responsible for supplying the following functions:
  #   on_connect(frame, login, passcode, host, session_id) - handle connect request from
  #     client including any authentication
  #   on_message(frame, destination, message, content_type) - handle delivery of message
  #     from client to given destination
  #   on_subscribe(frame, id, destination, ack_setting) - subscribe client to messages
  #     from given destination
  #   on_unsubscribe(frame, id, destination) - remove existing subscription
  #   on_ack(frame, ack_id) - handle acknowledgement from client that message has
  #     been successfully processed
  #   on_nack(frame, ack_id) - handle negative acknowledgement from client for message
  #   on_error(frame, error) - handle notification from server that client or server
  #     request failed and that connection should be closed
  #   on_disconnect(frame, reason) - handle request from client to close connection
  # The above functions should raise ApplicationError for requests that violate their
  # server constraints.
  #
  class Server

    SUPPORTED_VERSIONS = ["1.0", "1.1", "1.2"]

    ACK_SETTINGS = {
      "1.0" => ["auto", "client"],
      "1.1" => ["auto", "client", "client-individual"],
      "1.2" => ["auto", "client", "client-individual"]
    }

    CLIENT_COMMANDS = [:stomp, :connect, :send, :subscribe, :unsubscribe, :ack, :nack, :begin, :commit, :abort, :disconnect]
    TRANSACTIONAL_COMMANDS = [:send, :ack, :nack, :begin, :commit, :abort]

    MIN_SEND_HEARTBEAT = 5000
    DESIRED_RECEIVE_HEARTBEAT = 60000

    attr_reader :version, :session_id, :server_name, :heartbeat

    # Create STOMP server
    #
    # @option options [String] :name of server using STOMP that is to be sent to client
    # @option options [String] :version of server using STOMP
    # @option options [Integer] :min_send_interval in msec that server is willing to guarantee;
    #   defaults to MIN_SEND_HEARTBEAT
    # @option options [Integer] :desired_receive_interval in msec for client to send heartbeats;
    #   defaults to DESIRED_RECEIVE_HEARTBEAT
    def initialize(options = {})
      @options = options
      @ack_id = 0
      @ack_ids = {} # message-id is key
      @subscribe_id = 0
      @subscribes = {} # destination is key
      @server_name = options[:name] + (options[:version] ? "/#{options[:version]}" : "") if options[:name]
      @parser = StompOut::Parser.new
      @transactions = {}
      @connected = false
    end

    # Report to server that an error was encountered locally
    # Not intended for use by end user of this class
    #
    # @param [String] error being reported
    #
    # @return [TrueClass] always true
    def report_error(error)
      frame = Frame.new("ERROR", {"message" => error})
      on_error(frame, error)
      true
    end

    # Determine whether connected to STOMP server
    #
    # @return [Boolean] true if connected, otherwise false
    def connected?
      !!@connected
    end

    # Stop service
    #
    # @return [TrueClass] always true
    def disconnect
      if @connected
        @heartbeat.stop if @heartbeat
        @connected = false
      end
      true
    end

    # Process data received over connection from client
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
      error(e)
    end

    ##################################
    ## STOMP server subclass functions
    ##################################

    # Send data over connection to client
    #
    # @param [String] data that is STOMP encoded
    #
    # @return [TrueClass] always true
    def send_data(data)
      raise "Not implemented"
    end

    # Handle connect request from client including any authentication
    #
    # @param [Frame] frame received from client
    # @param [String, NilClass] login name for authentication
    # @param [String, NilClass] passcode for authentication
    # @param [String] host to which client wishes to connect; this could be
    #   a virtual host or anything the application requires, or it may
    #   be arbitrary
    # @param [String] session_id uniquely identifying the given STOMP session
    #
    # @return [Boolean] true if connection accepted, otherwise false
    def on_connect(frame, login, passcode, host, session_id)
      raise "Not implemented"
    end

    # Handle delivery of message from client to given destination
    #
    # @param [Frame] frame received from client
    # @param [String] destination for message with format being application specific
    # @param [Object] message body
    # @param [String] content_type of message in MIME terms, e.g., "text/plain"
    #
    # @raise [ApplicationError] invalid destination
    #
    # @return [TrueClass] always true
    def on_message(frame, destination, message, content_type)
      raise "Not implemented"
    end

    # Subscribe client to messages from given destination
    #
    # @param [Frame] frame received from client
    # @param [String] id uniquely identifying subscription within given session
    # @param [String] destination from which client wishes to receive messages
    # @param [String] ack_setting for how client wishes to handle acknowledgements:
    #   "auto", "client", or "client-individual"
    #
    # @raise [ApplicationError] invalid destination
    #
    # @return [TrueClass] always true
    def on_subscribe(frame, id, destination, ack_setting)
      raise "Not implemented"
    end

    # Remove existing subscription
    #
    # @param [Frame] frame received from client
    # @param [String] id of an existing subscription
    # @param [String] destination for subscription
    #
    # @return [TrueClass] always true
    def on_unsubscribe(frame, id, destination)
      raise "Not implemented"
    end

    # Handle acknowledgement from client that message has been successfully processed
    #
    # @param [Frame] frame received from client
    # @param [String] id for acknowledgement assigned to previously sent message
    #
    # @return [TrueClass] always true
    def on_ack(frame, id)
      raise "Not implemented"
    end

    # Handle negative acknowledgement from client for message
    #
    # @param [Frame] frame received from client
    # @param [String] id for acknowledgement assigned to previously sent message
    #
    # @return [TrueClass] always true
    def on_nack(frame, id)
      raise "Not implemented"
    end

    # Handle notification that a client or server request failed and that the connection
    # should be closed
    #
    # @param [Frame, NilClass] frame for error that was sent to client; nil if failed to send
    # @param [ProtocolError, ApplicationError, Exception, String] error raised
    #
    # @return [TrueClass] always true
    def on_error(frame, error)
      raise "Not implemented"
    end

    # Handle request from client to close connection
    #
    # @param [Frame] frame received from client
    # @param [String] reason for disconnect
    #
    # @return [TrueClass] always true
    def on_disconnect(frame, reason)
      raise "Not implemented"
    end

    ########################
    ## STOMP Server Commands
    ########################

    # Send message from a subscribed destination to client using MESSAGE frame
    # - must set "destination" header with the destination to which the message was sent;
    #   should be identical to "destination" of SEND frame if sent using STOMP
    # - must set "message-id" header uniquely identifying message
    # - must set "subscription" header matching identifier of subscription receiving the message (only 1.1, 1.2)
    # - must set "ack" header identifying ack/nack uniquely for this connection if subscription
    #   specified "ack" header with mode "client" or "client-individual" (only 1.2)
    # - must set the frame body to the body of the message
    # - should set "content-length" and "content-type" headers if there is a body
    # - may set other application-specific headers
    #
    # @param [Hash] headers for message per requirements above but with "message-id"
    #   defaulting to generated UUID and "ack" defaulting to generated ID if not specified
    # @param [String] body of message
    #
    # @return [Array] message ID and ack ID; latter is nil if ack is in "auto" mode
    #
    # @raise [ProtocolError] not connected
    # @raise [ApplicationError] subscription not found, subscription does not match destination
    def message(headers, body)
      raise ProtocolError.new("Not connected") unless @connected
      frame = Frame.new(nil, (headers && headers.dup) || {})
      destination, subscribe_id = frame.require(@version, "destination" => [], "subscription" => ["1.0"])
      message_id = frame.headers["message-id"] ||= SimpleUUID::UUID.new.to_guid

      ack_id = nil
      if (subscribe = @subscribes[destination])
        if subscribe[:id] != subscribe_id && @version != "1.0"
          raise ApplicationError.new("Subscription does not match destination")
        end
        if subscribe[:ack] != "auto"
          # Create ack ID if there is none so that user of this server can rely
          # on always receiving an ack ID (as opposed to a message ID) on ack/nack
          # independent of STOMP version in use
          ack_id = if @version < "1.2"
            @ack_ids[message_id] = frame.headers.delete("ack") || (@ack_id += 1).to_s
          else
            frame.headers["ack"] ||= (@ack_id += 1).to_s
          end
        end
      else
        raise ApplicationError.new("Subscription not found")
      end

      send_frame("MESSAGE", frame.headers, body)
      [message_id, ack_id]
    end

    protected

    # Report to client using a RECEIPT frame that server has successfully processed a client frame
    # - must set "receipt-id" header with value from "receipt" header of frame for which
    #   receipt was requested
    # - the receipt is a cumulative acknowledgement that all previous frames have been
    #   received by server, although not necessarily yet processed; previously received
    #   frames should continue to get processed by the server if the client disconnects
    #
    # @param [String] id of receipt
    #
    # @return [TrueClass] always true
    def receipt(id)
      send_frame("RECEIPT", {"receipt-id" => id})
      true
    end

    # Report to client using an ERROR frame that an error was encountered when processing a frame
    # - must close connection after sending frame
    # - should set "message" header with short description of the error
    # - should set additional headers to help identify the original frame, e.g., set
    #   "receipt-id" header if frame in error contained a "receipt" header
    # - may set the frame body to contain more detailed information
    # - should set "content-length" and "content-type" headers if there is a body
    #
    # @param [Exception] error being reported
    #
    # @return [TrueClass] always true
    def error(exception)
      details = nil
      if exception.is_a?(ProtocolError) || exception.is_a?(ApplicationError)
        headers = exception.respond_to?(:headers) ? exception.headers : {}
        message = headers["message"] = exception.message
        if (frame = exception.frame)
          headers["receipt-id"] = frame.headers["receipt"] if frame.headers.has_key?("receipt") && frame.command != "CONNECT"
          frame = frame.to_s
          non_null_length = frame.rindex(NULL) - 1
          details = "Failed frame:\n-----\n#{frame[0..non_null_length]}\n-----"
        end
        frame = send_frame("ERROR", headers, details)
      else
        # Rescue this send given that this is an unexpected exception and the send too may
        # fail; do not want such an exception to keep the user of this class from being notified
        frame = send_frame("ERROR", {"message" => "Internal STOMP server error"}) rescue nil
      end
      on_error(frame, exception)
      true
    end

    ########################
    ## STOMP client commands
    ########################

    # Create STOMP level connection between client and server
    # - must contain "accept-version" header with comma-separated list of STOMP versions supported
    #   (only 1.1, 1.2); defaults to "1.0" if missing
    # - must send ERROR frame and close connection if client and server do not share any common
    #   protocol versions
    # - must contain "host" header with the name of virtual host to which client wants to connect
    #   (only 1.1, 1.2); if does not match a known virtual host, server supporting virtual hosting
    #   may select default or reject connection
    # - may contain "login" header identifying client for authentication
    # - may contain "passcode" header with password for authentication
    # - may contain "heart-beat" header with two positive integers separated by comma (only 1.1, 1.2);
    #   first integer indicates client support for sending heartbeats with 0 meaning cannot send and any
    #   other value indicating number of milliseconds between heartbeats it can guarantee; second integer
    #   indicates the heartbeats the client would like to receive with 0 meaning none and any other
    #   value indicating the desired number of milliseconds between heartbeats; defaults to no heartbeat
    # - if accepting connection, must send CONNECTED frame
    #   - must set "version" header with the version this session will use, which is the highest version
    #     that the client and server have in common
    #   - may set "heart-beat" header with the server's settings
    #   - may set "session" header uniquely identifying this session
    #   - may set "server" header with information about the server that must include server name,
    #     optionally followed by "/" and the server version number
    #
    # @param [Frame] frame received from client
    #
    # @return [TrueClass] always true
    #
    # @raise [ProtocolError] missing header, receipt not permitted, invalid login
    def receive_connect(frame)
      raise ProtocolError.new("Already connected", frame) if @connected
      @version = negotiate_version(frame)
      # No need to pass frame to ProtocolError because connect does not permit "receipt" header
      raise ProtocolError.new("Receipt not permitted", frame) if frame.headers["receipt"]
      host = frame.require(@version, "host" => ["1.0"])
      @session_id = SimpleUUID::UUID.new.to_guid
      headers = {"version" => @version, "session" => @session_id}
      if (rate = frame.headers["heart-beat"])
        @heartbeat = Heartbeat.new(self, rate, @options[:min_send_interval] || MIN_SEND_HEARTBEAT,
                                   @options[:desired_receive_interval] || DESIRED_RECEIVE_HEARTBEAT)
        headers["heart-beat"] = [@heartbeat.outgoing_rate, @heartbeat.incoming_rate].join(",")
      end
      headers["server"] = @server_name if @server_name
      if on_connect(frame, frame.headers["login"], frame.headers["passcode"], host, @session_id)
        @connected = true
        send_frame("CONNECTED", headers)
        @heartbeat.start if @heartbeat
      else
        raise ProtocolError.new("Invalid login", frame)
      end
      true
    end

    alias :receive_stomp :receive_connect

    # Receive message from client to be delivered to given destination in messaging system
    # - must send ERROR frame and close connection if server cannot process message
    # - must contain "destination" header
    # - should include "content-length" and "content-type" headers if there is a body
    # - may contain "transaction" header
    # - may contain other application-specific headers, e.g., for filtering
    #
    # @param [Frame] frame received from client
    #
    # @return [TrueClass] always true
    #
    # @raise [ProtocolError] missing header
    def receive_message(frame)
      destination = frame.require(@version, "destination" => [])
      content_type = frame.headers["content-type"] || "text/plain"
      on_message(frame, destination, frame.body, content_type)
      true
    end

    # Handle request from client to register to listen to a given destination
    # - must send ERROR frame and close connection if server cannot create the subscription
    # - must contain "destination" header
    # - any messages received on this destination will be delivered to client as MESSAGE frames
    # - may contain other server-specific headers to customize delivery
    # - must contain "id" header uniquely identifying subscription within given connection (optional for 1.0)
    # - may contain "ack" header with values "auto", "client", or "client-individual"; defaults to "auto"
    #   - "auto" mode means the client does not need to send ACK frames for messages it receives;
    #     the server will assume client has received messages as soon as it sends it to the client
    #   - "client" mode means the client must send ACK/NACK frames and if connection is lost without
    #     receiving ACK, server may redeliver the message to another client; ACK/NACK frames are treated
    #     as cumulative meaning an ACK/NACK acknowledges identified message and all previous
    #   - "client-individual" mode acts like "client" mode except ACK/NACK frames are not cumulative
    #
    # @param [Frame] frame received from client
    #
    # @return [TrueClass] always true
    #
    # @raise [ProtocolError] missing header, invalid ack setting
    def receive_subscribe(frame)
      destination, id = frame.require(@version, "destination" => [], "id" => ["1.0"])
      ack = frame.headers["ack"] || "auto"
      raise ProtocolError.new("Invalid 'ack' header", frame) unless ACK_SETTINGS[@version].include?(ack)
      # Assign ID for 1.0 if there is none, but at uniqueness risk if client sometimes specifies
      id ||= (@subscribe_id += 1).to_s
      @subscribes[destination] = {:id => id, :ack => ack}
      on_subscribe(frame, id, destination, ack)
      true
    end

    # Handle request from client to remove an existing subscription
    # - must contain "id" header identifying the subscription (optional for 1.0)
    # - must contain "destination" header identifying subscription if no "id" header (1.0 only)
    #
    # @param [Frame] frame received from client
    #
    # @return [TrueClass] always true
    #
    # @raise [ProtocolError] missing header
    def receive_unsubscribe(frame)
      id = destination = nil
      begin
        id = frame.require(@version, "id" => [])
      rescue ProtocolError
        raise if @version != "1.0"
        destination = frame.require(@version, "destination" => ["1.1", "1.2"])
      end
      unless destination
        @subscribes.each { |key, value| (destination = key; break) if value[:id] == id }
      end
      if (subscribe = @subscribes.delete(destination))
        on_unsubscribe(frame, id || subscribe[:id], destination)
      else
        raise ProtocolError.new("Subscription not found", frame)
      end
      true
    end

    # Handle acknowledgement from client that it has consumed a message for a subscription
    # with "ack" header set to "client" or "client-individual"
    # - must contain "id" header matching the "ack" header of the MESSAGE being acknowledged (1.2 only)
    # - must contain "message-id" header matching the header of the MESSAGE being acknowledged (1.0, 1.1 only)
    # - may contain "transaction" header indicating acknowledging as part of the named transaction
    #
    # @param [Frame] frame received from client
    #
    # @return [TrueClass] always true
    #
    # @raise [ProtocolError] missing header
    def receive_ack(frame)
      id, message_id = frame.require(@version, "id" => ["1.0", "1.1"], "message-id" => ["1.2"])
      on_ack(frame, id || @ack_ids.delete(message_id))
      true
    end

    # Handle negative acknowledgement from client indicating that a message was not consumed (only 1.2)
    # - must contain "id" header matching the "ack" header of the MESSAGE not consumed (1.2 only)
    # - may contain "transaction" header indicating not acknowledging as part of the named transaction
    #
    # @param [Frame] frame received from client
    #
    # @return [TrueClass] always true
    #
    # @raise [ProtocolError] missing header, invalid command
    def receive_nack(frame)
      raise ProtocolError.new("Invalid command", frame) if @version == "1.0"
      id, message_id = frame.require(@version, "id" => ["1.0", "1.1"], "message-id" => ["1.2"])
      on_nack(frame, id || @ack_ids.delete(message_id))
      true
    end

    # Handle request from client to start a transaction such that any messages sent or
    # acknowledged during the transaction are processed atomically based on the transaction
    # - must contain "transaction" header uniquely identifying the transaction within given connection;
    #   value is used in associated SEND, ACK, NACK, COMMIT, and ABORT frames
    # - any started transactions which have not been committed are implicitly aborted if the
    #   client sends a DISCONNECT or the connection fails
    #
    # @param [Frame] frame received from client
    #
    # @return [TrueClass] always true
    #
    # @raise [ProtocolError] missing header, transaction already exists
    def receive_begin(frame)
      transaction = frame.require(@version, "transaction" => [])
      raise ProtocolError.new("Transaction already exists", frame) if @transactions.has_key?(transaction)
      @transactions[transaction] = []
      true
    end

    # Handle request from client to commit a transaction in progress
    # - must contain "transaction" header of an existing transaction
    #
    # @param [Frame] frame received from client
    #
    # @return [TrueClass] always true
    #
    # @raise [ProtocolError] missing header, transaction not found
    def receive_commit(frame)
      transaction = frame.require(@version, "transaction" => [])
      raise ProtocolError.new("Transaction not found", frame) unless @transactions.has_key?(transaction)
      (@transactions[transaction]).each do |f|
        f.headers.delete("transaction")
        process_frame(f)
      end
      @transactions.delete(transaction)
      true
    end

    # Handle request from client to roll back a transaction in progress
    # - must contain "transaction" header of an existing transaction
    #
    # @param [Frame] frame received from client
    #
    # @return [TrueClass] always true
    #
    # @raise [ProtocolError] missing header, transaction not found
    def receive_abort(frame)
      transaction = frame.require(@version, "transaction" => [])
      raise ProtocolError.new("Transaction not found", frame) unless @transactions.has_key?(transaction)
      @transactions.delete(transaction)
    end

    # Handle request from client to close the connection
    # - may contain "receipt" header
    # - no other frames should be received from client after this
    #
    # @param [Frame] frame received from client
    #
    # @return [TrueClass] always true
    def receive_disconnect(frame)
      on_disconnect(frame, "client request")
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

    # Process frame received from client, if necessary within a transaction
    #
    # @param [Frame] frame received from client
    #
    # @return [TrueClass] always true
    #
    # @raise [ProtocolError] unhandled frame, not connected, transaction not permitted
    def process_frame(frame)
      command = frame.command.downcase.to_sym
      raise ProtocolError.new("Unhandled frame: #{frame.command}", frame) unless CLIENT_COMMANDS.include?(command)
      raise ProtocolError.new("Not connected", frame) if !@connected && ![:stomp, :connect].include?(command)

      if (transaction = frame.headers["transaction"])
        raise ProtocolError.new("Transaction not permitted", frame) unless TRANSACTIONAL_COMMANDS.include?(command)
        handle_transaction(frame, transaction, command)
      else
        send((command == :send) ? :receive_message : ("receive_" + command.to_s).to_sym, frame)
      end

      receipt(frame.headers["receipt"]) if frame.headers["receipt"] && ![:stomp, :connect].include?(command)
      true
    end

    # Send frame to client
    #
    # @param [String] command name
    # @param [Hash, NilClass] headers for frame; others added if there is a body
    # @param [String, NilClass] body of message
    #
    # @return [Frame] frame sent
    #
    # @raise [ProtocolError] not connected
    def send_frame(command, headers = nil, body = nil)
      raise ProtocolError.new("Not connected") if !@connected && command != "ERROR"
      headers ||= {}
      if body && !body.empty?
        headers["content-type"] ||= "text/plain"
        headers["content-length"] = body.size.to_s
      else
        body = ""
      end
      frame = StompOut::Frame.new(command, headers, body)
      send_data(frame.to_s)
      @heartbeat.sent_data if @heartbeat
      frame
    end

    # Handle command being requested in the context of a transaction
    #
    # @param [Frame] frame received from client
    # @param [String] transaction identifier
    # @param [Symbol] command name
    #
    # @return [TrueClass] always true
    #
    # @raise [ProtocolError] transaction not found
    def handle_transaction(frame, transaction, command)
      if [:begin, :commit, :abort].include?(command)
        send(("receive_" + command.to_s).to_sym, frame)
      else
        raise ProtocolError.new("Transaction not found", frame) unless @transactions.has_key?(transaction)
        @transactions[transaction] << frame
      end
      true
    end

    # Determine STOMP version to be applied based on what client can support and
    # what this server can support; generate error if there is no common version
    #
    # @param [Frame] frame received from client
    #
    # @return [String] version chosen
    #
    # @raise [ProtocolError] incompatible version
    def negotiate_version(frame)
      if (accept = frame.headers["accept-version"])
        version = nil
        accepts = accept.split(",")
        SUPPORTED_VERSIONS.reverse.each { |v| (version = v; break) if accepts.include?(v) }
        raise ProtocolError.new("Incompatible version", frame, {"version" => SUPPORTED_VERSIONS.join(",")}) if version.nil?
      else
        version = SUPPORTED_VERSIONS.first
      end
      version
    end

  end # Server

end # StompOut
