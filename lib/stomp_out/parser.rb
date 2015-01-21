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

  # Null terminator for frame
  NULL = "\000"

  # Parser for converting stream of data from connection into STOMP frames
  class Parser

    # Create frame parser
    def initialize
      @buffer = ""
      @body_length = nil
      @frame = Frame.new
      @frames = []
    end

    # Add data received from connection to end of buffer
    #
    # @return [TrueClass] always true
    def <<(buf)
      @buffer << buf
      parse
    end

    # Get next frame
    #
    # @return [Frame, NilClass] frame or nil if none available
    def next
      @frames.shift
    end

    protected

    # Parse the contents of the buffer
    #
    # @return [TrueClass] always true
    def parse
      parse_command_and_headers if @frame.command.nil?
      success = if @frame.command
        if @body_length
          parse_binary_body
        else
          parse_text_body
        end
      elsif (match = @buffer.match(/\A\n|\A\r|\A\r\n/))
        # Ignore heartbeat
        @buffer = match.post_match
        true
      end

      # Keep parsing if making progress and there is more data
      parse if success && !@buffer.empty?
      true
    end

    # Parse next command and headers at beginning of buffer
    #
    # @return [TrueClass] always true
    def parse_command_and_headers
      if (match = @buffer.match(/\A\s*(\S+)\r?\n((?:[ \t]*.*?[ \t]*:[ \t]*.*?[ \t]*$\r?\n)*)\r?\n/))
        @frame.command, headers = match.captures
        @buffer = match.post_match
        headers.split(/\r?\n/).each do |data|
          if data.match(/^\s*(\S+)\s*:\s*(.*?\s*)$/)
            @frame.headers[$1] = $2 unless @frame.headers.has_key?($1)
          end
        end
        @body_length = (length = @frame.headers["content-length"]) && length.to_i
      elsif @buffer.rindex(NULL)
        raise ProtocolError, "Invalid frame (malformed headers)"
      end
      true
    end

    # Parse binary body at beginning of buffer
    #
    # @return [Frame, NilClass] frame created or nil if need more data
    #
    # @raise [ProtocolError] missing frame null terminator
    def parse_binary_body
      if @buffer.size > @body_length
        # Also test for 0 here to be compatible with Ruby 1.8 string handling
        unless [NULL, 0].include?(@buffer[@body_length])
          raise ProtocolError, "Invalid frame (missing null terminator)"
        end
        parse_body(@body_length)
      end
    end

    # Parse text body at beginning of buffer
    #
    # @return [Frame, NilClass] frame created or nil if need more data
    def parse_text_body
      if (length = @buffer.index(NULL))
        parse_body(length)
      end
    end

    # Parse body at beginning of buffer to complete frame
    #
    # @param [Integer] length of body
    #
    # @return [Frame] new frame
    def parse_body(length)
      @frame.body = @buffer[0...length]
      @buffer = @buffer[length+1..-1]
      @frames << @frame
      @frame = Frame.new
    end

  end # Parser

end # StompOut
