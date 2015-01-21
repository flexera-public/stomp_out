require 'spec_helper'

describe StompOut::Frame do

  context :initialize do
    it "defaults to empty frame" do
      frame = StompOut::Frame.new
      frame.command.should be nil
      frame.headers.should == {}
      frame.body.should == ""
    end

    it "initializes command, headers, and body" do
      frame = StompOut::Frame.new("MESSAGE", {"destination" => "/queue"}, "hello")
      frame.command.should == "MESSAGE"
      frame.headers.should == {"destination" => "/queue"}
      frame.body.should == "hello"
    end
  end

  context :to_s do
    it "serializes the frame" do
      frame = StompOut::Frame.new("MESSAGE", {"destination" => "/queue"}, "hello")
      frame.to_s.should == "MESSAGE\ndestination:/queue\n\nhello\000\n"
    end

    it "adds content-length header if body is binary" do
      frame = StompOut::Frame.new("MESSAGE", {}, "hell\000")
      frame.to_s.should == "MESSAGE\ncontent-length:5\n\nhell\000\000\n"
    end

    it "handles an empty frame" do
      frame = StompOut::Frame.new
      frame.to_s.should == "\n\n\000\n"
    end
  end

  context :require do
    before(:each) do
      @frame = StompOut::Frame.new("MESSAGE", {"destination" => "/queue"}, "hello")
    end

    it "does not raise ProtocolError if required headers are present" do
      @frame.require("1.1", "destination" => []).should == "/queue"
    end

    it "verifies multiple headers and returns array of values in sorted order" do
      @frame = StompOut::Frame.new("MESSAGE", {"destination" => "/queue", "message-id" => "123"}, "hello")
      @frame.require("1.0", "message-id" => [], "subscription" => ["1.0"], "destination" => []).should == ["/queue", "123", nil]
    end

    it "raises ProtocolError if required headers are missing" do
      lambda do
        @frame.require("1.1", "subscription" => ["1.0"])
      end.should raise_error(StompOut::ProtocolError, "Missing 'subscription' header")
    end

    it "only raises ProtocolError if version in use is not excluded" do
      @frame.require("1.0", "subscription" => ["1.0"]).should == nil
    end
  end
end
