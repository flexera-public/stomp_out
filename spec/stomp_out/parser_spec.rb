require 'spec_helper'

describe StompOut::Parser do

  before(:each) do
    @parser = StompOut::Parser.new
    @message = ""
  end

  context :initialize do
    it "initializes initial frame" do
      @parser.instance_variable_get(:@frames).should == []
      frame = @parser.instance_variable_get(:@frame)
      frame.command.should be nil
      frame.headers.should == {}
      frame.body.should == ""
    end
  end

  context :<< do
    it "stores data in buffer and then invokes parser" do
      @parser << "MESSAGE\ndestination:/queue\n\nhello\000\n"
      frame = @parser.next
      frame.command.should == "MESSAGE"
      frame.headers.should == {"destination" => "/queue"}
      frame.body.should == "hello"
      @parser.instance_variable_get(:@buffer).should == ""
    end

    it "handles receiving frame of data incrementally" do
      @parser << "MESSAGE\ndestination:/queue\n"
      @parser.next.should be nil
      @parser << "\nhello\000"
      frame = @parser.next
      frame.command.should == "MESSAGE"
      frame.headers.should == {"destination" => "/queue"}
      frame.body.should == "hello"
      @parser.instance_variable_get(:@buffer).should == ""
    end
  end

  context :next do
    it "returns next frame" do
      @parser << "MESSAGE\ndestination:/queue\n\nhello\000\n"
      frame = @parser.next
      frame.command.should == "MESSAGE"
      frame.headers.should == {"destination" => "/queue"}
      frame.body.should == "hello"
    end

    it "returns nil if there are no frames available" do
      @parser.next.should be nil
    end
  end

  context :parse do
    it "parses command and headers if not yet parsed for current frame" do
      @parser << "MESSAGE\ndestination:/queue\n\n"
      @parser.instance_variable_get(:@frame).command.should == "MESSAGE"
      @parser.instance_variable_get(:@frame).headers.should == {"destination" => "/queue"}
      @parser.instance_variable_get(:@frame).body.should == ""
      @parser.next.should be nil
      @parser << "hello\000"
      @parser.next.body.should == "hello"
    end

    it "parses empty headers" do
      @parser << "MESSAGE\n\nhello\000\n"
      frame = @parser.next
      frame.command.should == "MESSAGE"
      frame.headers.should == {}
      frame.body.should == "hello"
    end

    it "parses multiple headers" do
      @parser << "MESSAGE\ndestination:/queue\nsubscription:123\n\nhello\000\n"
      @parser.next.headers.should == {"destination" => "/queue", "subscription" => "123"}
    end

    it "raises ProtocolError if headers are malformed" do
      lambda do
        @parser << "MESSAGE\ndestination/queue\nsubscription:123\n\nhello\000\n"
      end.should raise_error(StompOut::ProtocolError, "Invalid frame (malformed headers)")
    end

    it "parses body with binary data" do
      @parser << "MESSAGE\ncontent-length:5\n\nh\000ll\010\000\n"
      frame = @parser.next
      frame.command.should == "MESSAGE"
      frame.headers.should == {"content-length" => "5"}
      frame.body.should == "h\00ll\010"
    end

    it "parses empty body" do
      @parser << "MESSAGE\ndestination:/queue\n\n\000\n"
      frame = @parser.next
      frame.command.should == "MESSAGE"
      frame.headers.should == {"destination" => "/queue"}
      frame.body.should == ""
    end

    it "parses empty headers and body" do
      @parser << "MESSAGE\n\n\000\n"
      frame = @parser.next
      frame.command.should == "MESSAGE"
      frame.headers.should == {}
      frame.body.should == ""
    end

    it "parses header whose value contains a ':'" do
      @parser << "MESSAGE\ndestination:/que:ue:\n\n\000\n"
      frame = @parser.next
      frame.command.should == "MESSAGE"
      frame.headers.should == {"destination" => "/que:ue:"}
    end

    context "when content-length header" do
      it "uses it to determine length of body" do
        @parser << "MESSAGE\ncontent-length:6\n\nhello\n\000"
        frame = @parser.next
        frame.body.should == "hello\n"
      end

      it "does not finish body until enough data is available" do
        @parser << "MESSAGE\ncontent-length:11\n\nhello"
        @parser.next.should be nil
        @parser << " world\000"
        frame = @parser.next
        frame.body.should == "hello world"
      end

      it "raises ProtocolError if there is no null terminator when expected" do
        lambda do
          @parser << "MESSAGE\ncontent-length:5\n\nhello \000"
        end.should raise_error(StompOut::ProtocolError, "Invalid frame (missing null terminator)")
      end
    end

    context "when no content-length header" do
      it "uses null terminator to find end of body" do
        @parser << "MESSAGE\n\nhello\n\000"
        frame = @parser.next
        frame.body.should == "hello\n"
      end

      it "does not finish body until enough data available" do
        @parser << "MESSAGE\n\nhello"
        @parser.next.should be nil
        @parser << " world\000"
        frame = @parser.next
        frame.body.should == "hello world"
      end

      it "raises ProtocolError if there is no null terminator" do
        lambda do
          @parser << "MESSAGE\ncontent-length:5\n\nhello \000"
        end.should raise_error(StompOut::ProtocolError, "Invalid frame (missing null terminator)")
      end
    end

    it "handles CR LF as end-of-line" do
      @parser << "MESSAGE\r\ndestination:/queue\r\n\r\nhello\r\n\000\r\n"
      frame = @parser.next
      frame.body.should == "hello\r\n"
    end

    it "discards heartbeat EOLs between frames" do
      @parser << "\n\r\n\r\n\n"
      @parser.next.should be nil
      @parser.instance_variable_get(:@buffer).should be_empty
    end

    it "continues parsing if successful and there is more data" do
      @parser << "MESSAGE\n\nhello\000\nMESSAGE\n\nworld\000"
      @parser.next.body.should == "hello"
      @parser.next.body.should == "world"
    end
  end
end
