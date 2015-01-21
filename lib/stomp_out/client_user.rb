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

  # Mock with user callback interface as required by Client
  # For use in testing and to document the callback interface
  class ClientUser

    attr_reader :called, :data, :frame, :session_id, :server_name, :destination, :message, :content_type,
                :message_id, :ack_id, :receipt_id, :error, :details

    def initialize
      @called = []
    end

    # Send data over connection to server
    #
    # @param [String] data that is STOMP encoded
    #
    # @return [TrueClass] always true
    def send_data(data)
      @called << :send_data
      @data = data
      true
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
      @called << :on_connected
      @frame = frame
      @session_id = session_id
      @server_name = server_name
      true
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
      @called << :on_message
      @frame = frame
      @destination = destination
      @message = message
      @content_type = content_type
      @message_id = message_id
      @ack_id = ack_id
      true
    end

    # Handle notification that a request was successfully handled by server
    #
    # @param [Frame] frame received from server
    # @param [String] receipt_id identifying request completed (client request
    #   functions optionally return a receipt_id)
    #
    # @return [TrueClass] always true
    def on_receipt(frame, receipt_id)
      @called << :on_receipt
      @frame = frame
      @receipt_id = receipt_id
      true
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
      @called << :on_error
      @frame = frame
      @error = error
      @details = details
      @receipt_id = receipt_id
      true
    end

  end # ClientUser

end # StompOut
