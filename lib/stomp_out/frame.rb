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

  # Container for STOMP frame
  class Frame

    attr_accessor :command, :headers, :body

    # Create Stomp frame
    #
    # @param [String, NilClass] command name in upper case
    # @param [Hash, NilClass] headers with string header name as key
    # @param [String] body
    def initialize(command = nil, headers = nil, body = nil)
      @command = command
      @headers = headers || {}
      @body = body || ""
    end

    # Serialize frame for transmission on wire
    #
    # @return [String] serialized frame
    def to_s
      @headers["content-length"] = @body.size.to_s if @body.include?(NULL)
      @headers.keys.sort.inject("#{@command}\n") { |r, key| r << "#{key}:#{@headers[key]}\n" } + "\n#{@body}#{NULL}\n"
    end

    # Verify that required headers are present and then return their values
    #
    # @param [String] version of STOMP in use
    # @param [Hash] required headers with name as key and list of STOMP versions
    #   to be excluded from the verification as value
    #
    # @return [Array, Object] values of selected headers in header name sorted order,
    #   or individual header value if only one header required
    #
    # @raise [ProtocolError] missing header
    def require(version, required)
      values = []
      required.keys.sort.each do |header|
        exclude = required[header]
        value = @headers[header]
        raise ProtocolError.new("Missing '#{header}' header", self) if value.nil? && !exclude.include?(version)
        values << value
      end
      values.size > 1 ? values : values.first
    end

  end # Frame

end # StompOut
