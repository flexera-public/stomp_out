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

  # Mock that provides user callback interface required by Server
  # For use in testing and to document the callback interface
  class ServerUser

    attr_reader :called, :data, :frame, :login, :passcode, :host, :session_id, :destination, :message,
                :content_type, :subscribe_id, :ack_setting, :ack_id, :details, :error, :reason

    def initialize
      @called = []
    end

    # Send data over connection to client
    #
    # @param [String] data that is STOMP encoded
    #
    # @return [TrueClass] always true
    def send_data(data)
      @called << :send_data
      @data = data
      true
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
      @called << :on_connect
      @frame = frame
      @login = login
      @passcode = passcode
      @host = host
      @session_id = session_id
      true
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
      @called << :on_message
      @frame = frame
      @destination = destination
      @message = message
      @content_type = content_type
      true
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
      @called << :on_subscribe
      @frame = frame
      @subscribe_id = id
      @destination = destination
      @ack_setting = ack_setting
      true
    end

    # Remove existing subscription
    #
    # @param [Frame] frame received from client
    # @param [String] id of an existing subscription
    # @param [String] destination for subscription
    #
    # @return [TrueClass] always true
    def on_unsubscribe(frame, id, destination)
      @called << :on_unsubscribe
      @frame = frame
      @subscribe_id = id
      @destination = destination
      true
    end

    # Handle acknowledgement from client that message has been successfully processed
    #
    # @param [Frame] frame received from client
    # @param [String] id for acknowledgement assigned to previously sent message
    #
    # @return [TrueClass] always true
    def on_ack(frame, id)
      @called << :on_ack
      @frame = frame
      @ack_id = id
      true
    end

    # Handle negative acknowledgement from client for message
    #
    # @param [Frame] frame received from client
    # @param [String] id for acknowledgement assigned to previously sent message
    #
    # @return [TrueClass] always true
    def on_nack(frame, id)
      @called << :on_nack
      @frame = frame
      @ack_id = id
      true
    end

    # Handle notification that a client or server request failed and that the connection
    # should be closed
    #
    # @param [Frame, NilClass] frame for error that was sent to client; nil if failed to send
    # @param [ProtocolError, ApplicationError, Exception, String] error raised
    #
    # @return [TrueClass] always true
    def on_error(frame, error)
      @called << :on_error
      @frame = frame
      @error = error
      true
    end

    # Handle request from client to close connection
    #
    # @param [Frame] frame received from client
    # @param [String] reason for disconnect
    #
    # @return [TrueClass] always true
    def on_disconnect(frame, reason)
      @called << :on_disconnect
      @frame = frame
      @reason = reason
      true
    end

  end # ServerUser

end # StompOut
