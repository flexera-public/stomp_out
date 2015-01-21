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

  class Heartbeat

    # EOL that acts as STOMP heartbeat
    HEARTBEAT = "\n"

    # Error margin for receiving heartbeats
    ERROR_MARGIN_FACTOR = 1.5

    attr_reader :incoming_rate, :outgoing_rate

    # Determine whether heartbeat is usable based on whether eventmachine is available
    #
    # @return [Boolean] whether usable
    def self.usable?
      require 'eventmachine'
      true
    rescue LoadError => e
      false
    end

    # Analyze heartbeat request and if there is an agreeable rate start generating
    # heartbeats and/or monitoring incoming heartbeats
    #
    # @param [Client, Server] stomp client/server requesting heartbeat service that responds
    #   to the following callbacks:
    #   send_data(data) - send data over connection
    #   report_error(error) - report error to user
    # @param [String, NilClass] rate_requested requested with two positive integers separated
    #   by comma; first integer indicates far end's support for sending heartbeats with 0 meaning
    #   cannot send and any other value indicating number of milliseconds between heartbeats
    #   it can guarantee; second integer indicates the heartbeats the far end would like
    #   to receive with 0 meaning none and any other value indicating the desired number
    #   of milliseconds between heartbeats
    # @param [Integer] min_send_interval in msec that near end is willing to guarantee
    # @param [Integer] desired_receive_interval in msec for far end to send heartbeats
    #
    # @raise [ProtocolError] invalid heartbeat setting
    def initialize(stomp, rate_requested, min_send_interval = 0, desired_receive_interval = 0)
      @stomp = stomp
      @received_data = @sent_data = false
      @incoming_rate = @outgoing_rate = 0
      if rate_requested
        @incoming_rate, @outgoing_rate = rate_requested.split(",").map do |h|
          raise StompOut::ProtocolError, "Invalid 'heart-beat' header" if h.nil? || h !~ /^\d+$/
          h.to_i
        end
        raise StompOut::ProtocolError, "Invalid 'heart-beat' header" if @outgoing_rate.nil? || @incoming_rate.nil?
        @incoming_rate = [@incoming_rate, min_send_interval].max if @incoming_rate > 0
        @outgoing_rate = [@outgoing_rate, desired_receive_interval].max if @outgoing_rate > 0
      end
    end

    # Start heartbeat service
    #
    # @return [TrueClass] always true
    def start
      monitor_incoming if @incoming_rate > 0
      generate_outgoing if @outgoing_rate > 0
    end

    # Stop heartbeat service
    #
    # @return [TrueClass] always true
    def stop
      if @incoming_timer
        @incoming_timer.cancel
        @incoming_timer = nil
      end
      if @outgoing_timer
        @outgoing_timer.cancel
        @outgoing_timer = nil
      end
      true
    end

    # Record that data has been sent to far end
    #
    # @return [TrueClass] always true
    def sent_data
      @sent_data = true
    end

    # Record that data has been received from far end
    #
    # @return [TrueClass] always true
    def received_data
      @received_data = true
    end

    protected

    # Monitor incoming heartbeats
    # Report failure and stop heartbeat if miss heartbeat by more than
    # specified margin
    #
    # @return [TrueClass] always true
    def monitor_incoming
      interval = (@incoming_rate * ERROR_MARGIN_FACTOR) / 1000.0
      @incoming_timer = EM::PeriodicTimer.new(interval) do
        if @received_data
          @received_data = false
        else
          stop
          @stomp.report_error("heartbeat failure")
        end
      end
      true
    end

    # Generate outgoing heartbeats whenever there is not any other
    # send activity for given heartbeat interval
    #
    # @return [TrueClass] always true
    def generate_outgoing
      interval = @outgoing_rate / 1000.0
      @outgoing_timer = EM::PeriodicTimer.new(interval) do
        if @sent_data
          @sent_data = false
        else
          @stomp.send_data(HEARTBEAT)
        end
      end
    end

  end # Heartbeat

end # StompOut
