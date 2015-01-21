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

  # Exception for STOMP protocol violations
  class ProtocolError < RuntimeError

    # [Hash] Headers to be included in an ERROR response
    attr_reader :headers

    # [String, NilClass] Contents of "receipt" header in frame causing error
    attr_reader :receipt

    # [Frame, NilClass] Frame for which error occurred
    attr_reader :frame

    # Create exception
    #
    # @param [String] message describing error
    # @param [Frame, NilClass] frame that caused error
    # @param [Hash, NilClass] headers to be included in an ERROR response
    def initialize(message, frame = nil, headers = nil)
      @frame = frame
      @headers = headers || {}
      super(message)
    end

  end

  # Exception for application level STOMP protocol violations, i.e.,
  # for any additional rules that the application applying STOMP imposes
  class ApplicationError < RuntimeError

    # [Frame, NilClass] Frame for which error occurred
    attr_reader :frame

    # Create exception
    #
    # @param [String] message describing error
    # @param [Frame, NilClass] frame that caused error
    def initialize(message, frame = nil)
      @frame = frame
      super(message)
    end

  end

end # StompOut