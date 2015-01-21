require 'spec_helper'

describe StompOut::ProtocolError do

  context :initialize do
    it "initializes message, headers, receipt, and frame" do
      frame = StompOut::Frame.new("MESSAGE", {"receipt" => "123"}, "message")
      error = StompOut::ProtocolError.new("Missing header", frame, {"version" => "1.1"})
      error.message.should == "Missing header"
      error.headers.should == {"version" => "1.1"}
      error.frame.should == frame
    end
  end
end

describe StompOut::ApplicationError do

  context :initialize do
    it "initializes message and frame" do
      frame = StompOut::Frame.new("MESSAGE", {"ack" => "123"}, "message")
      error = StompOut::ApplicationError.new("Duplicate ack", frame)
      error.message.should == "Duplicate ack"
      error.frame.should == frame
    end
  end
end