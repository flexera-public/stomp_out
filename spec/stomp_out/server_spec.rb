require 'spec_helper'

# Mock server with subclass interface as required by Server
class ServerMock < StompOut::Server
  attr_reader :called, :params

  def initialize(options = {})
    @called = []
    @params = {}
    super
  end

  def send_data(data)
    @called << :send_data
    @params[:data] = data
  end

  def on_connect(frame, login, passcode, host, session_id)
    @called << :on_connect
    @params[:frame] = frame
    @params[:login] = login
    @params[:passcode] = passcode
    @params[:host] = host
    @params[:session_id] = session_id
    true
  end

  def on_message(frame, destination, message, content_type)
    @called << :on_message
    @params[:frame] = frame
    @params[:destination] = destination
    @params[:message] = message
    @params[:content_type] = content_type
    true
  end

  def on_subscribe(frame, id, destination, ack_setting)
    @called << :on_subscribe
    @params[:frame] = frame
    @params[:subscribe_id] = id
    @params[:destination] = destination
    @params[:ack_setting] = ack_setting
    true
  end

  def on_unsubscribe(frame, id, destination)
    @called << :on_unsubscribe
    @params[:frame] = frame
    @params[:subscribe_id] = id
    @params[:destination] = destination
    true
  end

  def on_ack(frame, id)
    @called << :on_ack
    @params[:frame] = frame
    @params[:ack_id] = id
  end

  def on_nack(frame, id)
    @called << :on_nack
    @params[:frame] = frame
    @params[:ack_id] = id
  end

  def on_error(frame, error)
    @called << :on_error
    @params[:frame] = frame
    @params[:error] = error
  end

  def on_disconnect(frame, reason)
    @called << :on_disconnect
    @params[:frame] = frame
    @params[:reason] = reason
  end
end

describe StompOut::Server do

  SERVER_SUPPORTED_VERSIONS = StompOut::Server::SUPPORTED_VERSIONS

  before(:each) do
    @options = {}
    @server = ServerMock.new(@options)
  end

  context :initialize do
    it "initializes attributes" do
      @server.connected?.should be false
      @server.version.should be nil
      @server.session_id.should be nil
      @server.server_name.should be nil
      @server.heartbeat.should be nil
    end

    it "uses options to set server name" do
      @options = {:name => "Server", :version => "1.0"}
      @server = ServerMock.new(@options)
      @server.server_name.should == "Server/1.0"
    end
  end

  context :receive_data do
    it "processes frame data" do
      @server.receive_data("CONNECT\naccept-version:1.0,1.1,1.2\nhost:stomp\n\n\000\n").should be true
      @server.called.should == [:on_connect, :send_data]
      @server.params[:frame].command.should == "CONNECT"
    end

    it "notifies heartbeat" do
      @server.receive_data("CONNECT\naccept-version:1.0,1.1,1.2\nheart-beat:0,0\nhost:stomp\n\n\000\n").should be true
      @server.heartbeat.instance_variable_get(:@received_data).should be true
    end

    it "reports error to client" do
      @server.receive_data("CONNECT\naccept-version:1.0,1.1,1.2\n\n\000\n").should be true
      @server.called.should == [:send_data, :on_error]
      @server.params[:data].should == "ERROR\ncontent-length:62\ncontent-type:text/plain\nmessage:Missing 'host' header\n" +
                                      "\nFailed frame:\n-----\nCONNECT\naccept-version:1.0,1.1,1.2\n\n\n-----\000\n"
      @server.params[:error].message.should == "Missing 'host' header"
    end
  end

  context :report_error do
    it "notifies user of the error" do
      @server.report_error("failed")
      @server.called.should == [:on_error]
      @server.params[:frame].command.should == "ERROR"
      @server.params[:error].should == "failed"
    end
  end

  context :disconnect do
    it "stops heartbeat" do
      @server.receive_data("CONNECT\naccept-version:1.0,1.1,1.2\nheart-beat:0,0\nhost:stomp\n\n\000\n")
      flexmock(@server.heartbeat).should_receive(:stop).once
      @server.disconnect
    end

    it "does nothing if already disconnected" do
      flexmock(@server.heartbeat).should_receive(:stop).never
      @server.disconnect
    end
  end

  context "server commands" do

    SERVER_SUPPORTED_VERSIONS.size.times do |i|
      versions = SERVER_SUPPORTED_VERSIONS[0..i].join(",")
      accept_version = versions == "1.0" ? nil : "\naccept-version:#{versions}"
      context versions do
        context :message do
          context "when connected" do
            before(:each) do
              @server.receive_data("CONNECT#{accept_version}\nhost:stomp\n\n\000\n")
              @server.receive_data("SUBSCRIBE\ndestination:/queue\nid:1\n\n\000\n")
              @headers = {"destination" => "/queue", "message-id" => "123", "subscription" => "1"}
              @uuid = flexmock("uuid", :to_guid => "uuid")
              flexmock(SimpleUUID::UUID).should_receive(:new).and_return(@uuid)
            end

            it "sends MESSAGE frame to client" do
              @server.message(@headers, "hello")
              @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data]
              @server.params[:data].should == "MESSAGE\ncontent-length:5\ncontent-type:text/plain\ndestination:/queue" +
                                              "\nmessage-id:123\nsubscription:1\n\nhello\000\n"
            end

            it "creates a unique message-id if none is specified" do
              @headers.delete("message-id")
              @server.message(@headers, "hello")
              @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data]
              @server.params[:data].should == "MESSAGE\ncontent-length:5\ncontent-type:text/plain\ndestination:/queue" +
                                              "\nmessage-id:uuid\nsubscription:1\n\nhello\000\n"
            end

            it "raises ProtocolError if destination header is missing" do
              @headers.delete("destination")
              lambda do
                @server.message(@headers, "hello")
              end.should raise_error(StompOut::ProtocolError, "Missing 'destination' header")
            end

            if versions == "1.0"
              it "does not raise ProtocolError if subscription header is missing" do
                @headers.delete("subscription")
                @server.message(@headers, "hello")
                @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data]
                @server.params[:data].should == "MESSAGE\ncontent-length:5\ncontent-type:text/plain\ndestination:/queue" +
                                                "\nmessage-id:123\n\nhello\000\n"
              end
            else
              it "raises ProtocolError if subscription header is missing" do
                @headers.delete("subscription")
                lambda do
                  @server.message(@headers, "hello")
                end.should raise_error(StompOut::ProtocolError, "Missing 'subscription' header")
              end

              it "raises ApplicationError if subscription does not match destination" do
                @headers["subscription"] = "2"
                lambda do
                  @server.message(@headers, "hello")
                end.should raise_error(StompOut::ApplicationError, "Subscription does not match destination")
              end
            end

            ["client", "client-individual"].each do |ack|
              context "when ack == #{ack}" do
                if versions == "1.0" && ack != "client-individual"
                  before(:each) do
                    @server.receive_data("UNSUBSCRIBE\ndestination:/queue\n\n\000\n")
                    @server.receive_data("SUBSCRIBE\nack:#{ack}\ndestination:/queue\n\n\000\n")
                    @headers["subscription"] = "2"
                  end

                  it "records specified ack ID but leaves it out of frame" do
                    @headers["ack"] = "11"
                    @server.message(@headers, "hello").should == ["123", "11"]
                    @server.instance_variable_get(:@ack_ids)["123"].should == "11"
                    @server.called.should == [:on_connect, :send_data, :on_subscribe, :on_unsubscribe, :on_subscribe, :send_data]
                    @server.params[:data].should == "MESSAGE\ncontent-length:5\ncontent-type:text/plain\ndestination:/queue" +
                                                    "\nmessage-id:123\nsubscription:2\n\nhello\000\n"
                  end

                  it "creates ack ID and records it but leaves it out of frame if none specified" do
                    @server.message(@headers, "hello").should == ["123", "1"]
                    @server.instance_variable_get(:@ack_ids)["123"].should == "1"
                    @server.called.should == [:on_connect, :send_data, :on_subscribe, :on_unsubscribe, :on_subscribe, :send_data]
                    @server.params[:data].should == "MESSAGE\ncontent-length:5\ncontent-type:text/plain\ndestination:/queue" +
                                                    "\nmessage-id:123\nsubscription:2\n\nhello\000\n"
                  end
                elsif versions != "1.0"
                  before(:each) do
                    @server.receive_data("UNSUBSCRIBE\nid:1\n\n\000\n")
                    @server.receive_data("SUBSCRIBE\nack:#{ack}\ndestination:/queue\nid:2\n\n\000\n")
                    @headers["subscription"] = "2"
                  end

                  if versions == "1.0,1.1"
                    it "records specified ack ID but leaves it out of frame" do
                      @headers["ack"] = "11"
                      @server.message(@headers, "hello").should == ["123", "11"]
                      @server.instance_variable_get(:@ack_ids)["123"].should == "11"
                      @server.called.should == [:on_connect, :send_data, :on_subscribe, :on_unsubscribe, :on_subscribe, :send_data]
                      @server.params[:data].should == "MESSAGE\ncontent-length:5\ncontent-type:text/plain\ndestination:/queue" +
                                                      "\nmessage-id:123\nsubscription:2\n\nhello\000\n"
                    end

                    it "creates ack ID and records it but leaves it out of frame if none specified" do
                      @server.message(@headers, "hello").should == ["123", "1"]
                      @server.instance_variable_get(:@ack_ids)["123"].should == "1"
                      @server.called.should == [:on_connect, :send_data, :on_subscribe, :on_unsubscribe, :on_subscribe, :send_data]
                      @server.params[:data].should == "MESSAGE\ncontent-length:5\ncontent-type:text/plain\ndestination:/queue" +
                                                      "\nmessage-id:123\nsubscription:2\n\nhello\000\n"
                    end
                  else
                    it "adds specified ack ID to frame" do
                      @headers["ack"] = "11"
                      @server.message(@headers, "hello").should == ["123", "11"]
                      @server.called.should == [:on_connect, :send_data, :on_subscribe, :on_unsubscribe, :on_subscribe, :send_data]
                      @server.params[:data].should == "MESSAGE\nack:11\ncontent-length:5\ncontent-type:text/plain\ndestination:/queue" +
                                                      "\nmessage-id:123\nsubscription:2\n\nhello\000\n"
                    end

                    it "creates ack ID and adds to frame if none specified" do
                      @server.message(@headers, "hello").should == ["123", "1"]
                      @server.called.should == [:on_connect, :send_data, :on_subscribe, :on_unsubscribe, :on_subscribe, :send_data]
                      @server.params[:data].should == "MESSAGE\nack:1\ncontent-length:5\ncontent-type:text/plain\ndestination:/queue" +
                                                      "\nmessage-id:123\nsubscription:2\n\nhello\000\n"
                    end
                  end
                end
              end
            end

            it "raises ApplicationError if subscription not found" do
              @headers["destination"] = "/queue2"
              lambda do
                @server.message(@headers, "hello")
              end.should raise_error(StompOut::ApplicationError, "Subscription not found")
            end
          end

          it "raises ProtocolError if not connected" do
            lambda do
              @server.message(nil, nil)
            end.should raise_error(StompOut::ProtocolError, "Not connected")
          end
        end

        context :receipt do
          it "sends RECEIPT frame to client" do
            @server.receive_data("CONNECT#{accept_version}\nhost:stomp\n\n\000\n")
            @server.receive_data("SUBSCRIBE\ndestination:/queue\nid:1\nreceipt:2\n\n\000\n")
            @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data]
            @server.params[:data].should == "RECEIPT\nreceipt-id:2\n\n\000\n"
          end
        end

        context :error do
          [StompOut::ProtocolError, StompOut::ApplicationError].each do |error_class|
            context error_class.name.split("::").last do
              it "sends ERROR frame to client and reports it to user" do
                frame = StompOut::Frame.new("CONNECT")
                error = error_class.new("Failed", frame)
                @server.send(:error, error).should be true
                @server.called.should == [:send_data, :on_error]
                @server.params[:error].should == error
              end

              it "stores error in message header" do
                error = error_class.new("Failed")
                @server.send(:error, error).should be true
                @server.called.should == [:send_data, :on_error]
                @server.params[:frame].to_s.should == "ERROR\nmessage:Failed\n\n\000\n"
              end

              if error_class == StompOut::ProtocolError
                it "applies headers associated with error" do
                  error = error_class.new("Failed", nil, "version" => "1.0,1.1")
                  @server.send(:error, error).should be true
                  @server.called.should == [:send_data, :on_error]
                  @server.params[:frame].to_s.should == "ERROR\nmessage:Failed\nversion:1.0,1.1\n\n\000\n"
                end
              end

              context "with frame" do
                it "adds receipt-id header if there is a receipt requested for non-CONNECT frame that had error" do
                  frame = StompOut::Frame.new("SEND", {"receipt" => "11"}, "hello")
                  error = error_class.new("Failed", frame)
                  @server.send(:error, error).should be true
                  @server.called.should == [:send_data, :on_error]
                  @server.params[:frame].to_s.should == "ERROR\ncontent-length:48\ncontent-type:text/plain\nmessage:Failed" +
                                             "\nreceipt-id:11\n\nFailed frame:\n-----\nSEND\nreceipt:11\n\nhello\n-----\000\n"
                end

                it "does not add receipt-id header to error frame if for a CONNECT frame that had an error" do
                  frame = StompOut::Frame.new("CONNECT", {"receipt" => "11"}, "hello")
                  error = error_class.new("Failed", frame)
                  @server.send(:error, error).should be true
                  @server.called.should == [:send_data, :on_error]
                  @server.params[:frame].to_s.should == "ERROR\ncontent-length:51\ncontent-type:text/plain\nmessage:Failed\n" +
                                             "\nFailed frame:\n-----\nCONNECT\nreceipt:11\n\nhello\n-----\000\n"
                end

                it "stores frame that failed in body excluding null terminator" do
                  frame = StompOut::Frame.new("SEND", nil, "hello")
                  error = error_class.new("Failed", frame)
                  @server.send(:error, error).should be true
                  @server.called.should == [:send_data, :on_error]
                  @server.params[:frame].to_s.should == "ERROR\ncontent-length:37\ncontent-type:text/plain\nmessage:Failed\n" +
                                             "\nFailed frame:\n-----\nSEND\n\nhello\n-----\000\n"
                end
              end
            end
          end

          context "Exception" do
            it "sends ERROR frame to client and reports it to user" do
              error = RuntimeError.new("failed")
              @server.send(:error, error).should be true
              @server.called.should == [:send_data, :on_error]
              @server.params[:error].should == error
            end

            it "indicates to client that this is an internal server error" do
              error = RuntimeError.new("failed")
              @server.send(:error, error).should be true
              @server.called.should == [:send_data, :on_error]
              @server.params[:frame].to_s.should == "ERROR\nmessage:Internal STOMP server error\n\n\000\n"
              @server.params[:error].message.should == "failed"
            end

            it "rescues attempt to send error to client so that user notification succeeds" do
              flexmock(@server).should_receive(:send_frame).and_raise(RuntimeError, "failed sending").once
              error = RuntimeError.new("failed")
              @server.send(:error, error).should be true
              @server.called.should == [:on_error]
              @server.params[:frame].should be nil
              @server.params[:error].message.should == "failed"
            end
          end
        end
      end
    end
  end

  context "client commands" do

    SERVER_SUPPORTED_VERSIONS.size.times do |i|
      version = SERVER_SUPPORTED_VERSIONS[i]
      versions = SERVER_SUPPORTED_VERSIONS[0..i].join(",")
      accept_version = versions == "1.0" ? nil : "\naccept-version:#{versions}"
      context versions do
        context :receive_connect do
          it "raises ProtocolError if already connected" do
            @server.receive_data("CONNECT#{accept_version}\nhost:stomp\n\n\000\n")
            @server.receive_data("CONNECT#{accept_version}\nhost:stomp\n\n\000\n")
            @server.called.should == [:on_connect, :send_data, :send_data, :on_error]
            @server.params[:error].message.should == "Already connected"
            length = 46 + (accept_version ? accept_version.size : 0)
            @server.params[:data].should == "ERROR\ncontent-length:#{length}\ncontent-type:text/plain\nmessage:Already connected\n" +
                                            "\nFailed frame:\n-----\nCONNECT#{accept_version}\nhost:stomp\n\n\n-----\000\n"
          end

          it "negotiates protocol version to use" do
            @server.receive_data("CONNECT#{accept_version}\nhost:stomp\n\n\000\n")
            @server.version.should == version
          end

          it "raises ProtocolError if receipt is requested by client" do
            @server.receive_data("CONNECT#{accept_version}\nhost:stomp\nreceipt:1\n\n\000\n")
            @server.called.should == [:send_data, :on_error]
            @server.params[:error].message.should == "Receipt not permitted"
            length = 56 + (accept_version ? accept_version.size : 0)
            @server.params[:data].should == "ERROR\ncontent-length:#{length}\ncontent-type:text/plain\nmessage:Receipt not permitted\n" +
                                            "\nFailed frame:\n-----\nCONNECT#{accept_version}\nhost:stomp\nreceipt:1\n\n\n-----\000\n"
          end

          if version == "1.0"
            it "does not require host header" do
              @server.receive_data("CONNECT#{accept_version}\n\n\000\n")
              @server.called.should == [:on_connect, :send_data]
              @server.params[:data].should =~ /CONNECTED/
            end
          else
            it "raises ProtocolError if host header is missing" do
              @server.receive_data("CONNECT#{accept_version}\n\n\000\n")
              @server.called.should == [:send_data, :on_error]
              @server.params[:error].message.should == "Missing 'host' header"
              length = 35 + (accept_version ? accept_version.size : 0)
              @server.params[:data].should == "ERROR\ncontent-length:#{length}\ncontent-type:text/plain\nmessage:Missing 'host' header\n" +
                                              "\nFailed frame:\n-----\nCONNECT#{accept_version}\n\n\n-----\000\n"
            end
          end

          context "with heartbeat" do
            before(:each) do
              @timer = flexmock("timer")
              flexmock(EM::PeriodicTimer).should_receive(:new).and_return(@timer).by_default
            end

            it "responds with none if client requests none" do
              @server.receive_data("CONNECT#{accept_version}\nheart-beat:0,0\nhost:stomp\n\n\000\n")
              @server.called.should == [:on_connect, :send_data]
              @server.params[:data].should =~ /CONNECTED.*\nheart-beat:0,0\n/
            end

            it "negotiates setting if client requests heartbeat and starts heartbeat" do
              flexmock(EM::PeriodicTimer).should_receive(:new).and_return(@timer).twice
              @server.receive_data("CONNECT#{accept_version}\nheart-beat:4000,10000\nhost:stomp\n\n\000\n")
              @server.called.should == [:on_connect, :send_data]
              @server.params[:data].should =~ /CONNECTED.*\nheart-beat:60000,5000\n/
            end

            it "uses user-specified limits when negotiating heartbeat setting and starts heartbeat" do
              flexmock(EM::PeriodicTimer).should_receive(:new).and_return(@timer).twice
              @server = ServerMock.new(@options.merge(:min_send_interval => 6000, :desired_receive_interval => 30000))
              @server.receive_data("CONNECT#{accept_version}\nheart-beat:4000,10000\nhost:stomp\n\n\000\n")
              @server.called.should == [:on_connect, :send_data]
              @server.params[:data].should =~ /CONNECTED.*\nheart-beat:30000,6000\n/
            end
          end

          it "sets server header if user specified server name" do
            @server = ServerMock.new(@options.merge(:name => "test", :version => "1.0"))
            @server.receive_data("CONNECT#{accept_version}\nhost:stomp\n\n\000\n")
            @server.called.should == [:on_connect, :send_data]
            @server.params[:data].should =~ /CONNECTED.*\nserver:test\/1.0\n/
          end

          it "uses on_connect returned value as session ID if it is a string" do
            flexmock(@server).should_receive(:on_connect).and_return("22").once
            @server.receive_data("CONNECT#{accept_version}\nhost:stomp\n\n\000\n")
            @server.called.should == [:send_data]
            @server.params[:session_id].should_not == "22"
            @server.params[:data].should =~ /CONNECTED.*\nsession:22\n/
          end

          it "uses on_connect returned value as session ID if it is an integer" do
            flexmock(@server).should_receive(:on_connect).and_return(22).once
            @server.receive_data("CONNECT#{accept_version}\nhost:stomp\n\n\000\n")
            @server.called.should == [:send_data]
            @server.params[:session_id].should_not == "22"
            @server.params[:data].should =~ /CONNECTED.*\nsession:22\n/
          end

          it "reports connection to user and allows it to be rejected" do
            flexmock(@server).should_receive(:on_connect).with(StompOut::Frame, "test", "secret", "stomp", String).
                and_return(false).once
            @server.receive_data("CONNECT#{accept_version}\nhost:stomp\nlogin:test\npasscode:secret\n\n\000\n")
            @server.called.should == [:send_data, :on_error]
            @server.params[:error].message.should == "Invalid login"
            length = 73 + (accept_version ? accept_version.size : 0)
            @server.params[:data].should == "ERROR\ncontent-length:#{length}\ncontent-type:text/plain\nmessage:Invalid login\n" +
                                            "\nFailed frame:\n-----\nCONNECT#{accept_version}\nhost:stomp\nlogin:test" +
                                            "\npasscode:secret\n\n\n-----\000\n"
          end

          it "sends CONNECTED frame to client if connection accepted" do
            uuid = flexmock("uuid", :to_guid => "uuid")
            flexmock(SimpleUUID::UUID).should_receive(:new).and_return(uuid)
            @server.receive_data("CONNECT#{accept_version}\nhost:stomp\nlogin:test\npasscode:secret\n\n\000\n")
            @server.called.should == [:on_connect, :send_data]
            @server.params[:data].should == "CONNECTED\nsession:uuid\nversion:#{version}\n\n\000\n"
          end
        end

        context :receive_stomp do
          it "sends CONNECTED frame to client if connection accepted" do
            uuid = flexmock("uuid", :to_guid => "uuid")
            flexmock(SimpleUUID::UUID).should_receive(:new).and_return(uuid)
            @server.receive_data("STOMP#{accept_version}\nhost:stomp\nlogin:test\npasscode:secret\n\n\000\n")
            @server.called.should == [:on_connect, :send_data]
            @server.params[:data].should == "CONNECTED\nsession:uuid\nversion:#{version}\n\n\000\n"
          end
        end

        context :receive_message do
          context "when connected" do
            before(:each) do
              @server.receive_data("CONNECT#{accept_version}\nhost:stomp\n\n\000\n")
            end

            it "raises ProtocolError if destination header is missing" do
              @server.receive_data("SEND\n\nhello\000\n")
              @server.called.should == [:on_connect, :send_data, :send_data, :on_error]
              @server.params[:error].message.should == "Missing 'destination' header"
              @server.params[:data].should == "ERROR\ncontent-length:37\ncontent-type:text/plain\nmessage:Missing 'destination' header\n" +
                                              "\nFailed frame:\n-----\nSEND\n\nhello\n-----\000\n"
            end

            it "reports message received to user" do
              @server.receive_data("SEND\ndestination:/queue\n\nhello\000\n")
              @server.called.should == [:on_connect, :send_data, :on_message]
              @server.params[:frame].command.should == "SEND"
              @server.params[:destination].should == "/queue"
              @server.params[:message].should == "hello"
              @server.params[:content_type].should == "text/plain"
            end

            it "sends receipt if requested" do
              @server.receive_data("SEND\ndestination:/queue\nreceipt:1\n\nhello\000\n")
              @server.called.should == [:on_connect, :send_data, :on_message, :send_data]
              @server.params[:data].should == "RECEIPT\nreceipt-id:1\n\n\000\n"
            end
          end

          it "raises ProtocolError if not connected" do
            @server.receive_data("SEND\ndestination:/queue\n\nhello\000\n")
            @server.called.should == [:send_data, :on_error]
            @server.params[:error].message.should == "Not connected"
            @server.params[:data].should == "ERROR\ncontent-length:56\ncontent-type:text/plain\nmessage:Not connected\n" +
                                            "\nFailed frame:\n-----\nSEND\ndestination:/queue\n\nhello\n-----\000\n"
          end
        end

        context :receive_subscribe do
          context "when connected" do
            before(:each) do
              @server.receive_data("CONNECT#{accept_version}\nhost:stomp\n\n\000\n")
            end

            it "raises ProtocolError if missing destination header" do
              @server.receive_data("SUBSCRIBE\n\n\000\n")
              @server.called.should == [:on_connect, :send_data, :send_data, :on_error]
              @server.params[:error].message.should == "Missing 'destination' header"
              @server.params[:data].should == "ERROR\ncontent-length:37\ncontent-type:text/plain\nmessage:Missing 'destination' header\n" +
                                              "\nFailed frame:\n-----\nSUBSCRIBE\n\n\n-----\000\n"
            end

            if version == "1.0"
              it "generates id if there is no id header" do
                @server.receive_data("SUBSCRIBE\ndestination:/queue\n\n\000\n")
                @server.instance_variable_get(:@subscribes).should == {"/queue" => {:id => "1", :ack => "auto"}}
              end
            else
              it "raises ProtocolError if missing id header" do
                @server.receive_data("SUBSCRIBE\ndestination:/queue\n\n\000\n")
                @server.called.should == [:on_connect, :send_data, :send_data, :on_error]
                @server.params[:error].message.should == "Missing 'id' header"
                @server.params[:data].should == "ERROR\ncontent-length:56\ncontent-type:text/plain\nmessage:Missing 'id' header\n" +
                                                "\nFailed frame:\n-----\nSUBSCRIBE\ndestination:/queue\n\n\n-----\000\n"
              end
            end

            ["auto", "client", "client-individual"].each do |ack|
              if version != "1.0" || ack != "client-individual"
                it "records #{ack} ack setting with subscription" do
                  @server.receive_data("SUBSCRIBE\nack:#{ack}\ndestination:/queue\nid:2\n\n\000\n")
                  @server.instance_variable_get(:@subscribes).should == {"/queue" => {:id => "2", :ack => ack}}
                end
              else
                it "raises ProtocolError if ack setting is invalid" do
                  @server.receive_data("SUBSCRIBE\nack:#{ack}\ndestination:/queue\nid:2\n\n\000\n")
                  @server.called.should == [:on_connect, :send_data, :send_data, :on_error]
                  @server.params[:error].message.should == "Invalid 'ack' header"
                end
              end
            end

            it "defaults ack setting to auto" do
              @server.receive_data("SUBSCRIBE\ndestination:/queue\nid:2\n\n\000\n")
              @server.instance_variable_get(:@subscribes).should == {"/queue" => {:id => "2", :ack => "auto"}}
            end

            it "raises ProtocolError if ack setting is invalid" do
              @server.receive_data("SUBSCRIBE\nack:bogus\ndestination:/queue\nid:2\n\n\000\n")
              @server.called.should == [:on_connect, :send_data, :send_data, :on_error]
              @server.params[:error].message.should == "Invalid 'ack' header"
              @server.params[:data].should == "ERROR\ncontent-length:71\ncontent-type:text/plain\nmessage:Invalid 'ack' header\n" +
                                              "\nFailed frame:\n-----\nSUBSCRIBE\nack:bogus\ndestination:/queue\nid:2\n\n\n-----\000\n"
            end

            it "reports successful subscribe to user" do
              @server.receive_data("SUBSCRIBE\nack:client\ndestination:/queue\nid:2\n\n\000\n")
              @server.called.should == [:on_connect, :send_data, :on_subscribe]
              @server.params[:frame].command.should == "SUBSCRIBE"
              @server.params[:subscribe_id].should == "2"
              @server.params[:destination].should == "/queue"
              @server.params[:ack_setting].should == "client"
            end

            it "sends receipt if requested" do
              @server.receive_data("SUBSCRIBE\nack:client\ndestination:/queue\nid:2\nreceipt:1\n\n\000\n")
              @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data]
              @server.params[:data].should == "RECEIPT\nreceipt-id:1\n\n\000\n"
            end
          end

          it "raises ProtocolError if not connected" do
            @server.receive_data("SUBSCRIBE\n\n\000\n")
            @server.called.should == [:send_data, :on_error]
            @server.params[:error].message.should == "Not connected"
            @server.params[:data].should == "ERROR\ncontent-length:37\ncontent-type:text/plain\nmessage:Not connected\n" +
                                            "\nFailed frame:\n-----\nSUBSCRIBE\n\n\n-----\000\n"
          end
        end

        context :receive_unsubscribe do
          context "when connected" do
            before(:each) do
              @server.receive_data("CONNECT#{accept_version}\nhost:stomp\n\n\000\n")
              @server.receive_data("SUBSCRIBE\nack:client\ndestination:/queue\nid:1\n\n\000\n")
            end

            if version == "1.0"
              it "raises ProtocolError if missing both id and destination headers" do
                @server.receive_data("UNSUBSCRIBE\n\n\000\n")
                @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data, :on_error]
                @server.params[:error].message.should == "Missing 'destination' header"
                @server.params[:data].should == "ERROR\ncontent-length:39\ncontent-type:text/plain\nmessage:Missing 'destination' header\n" +
                                                "\nFailed frame:\n-----\nUNSUBSCRIBE\n\n\n-----\000\n"
              end

              it "raises ProtocolError if subscription not found" do
                @server.receive_data("UNSUBSCRIBE\ndestination:/queue2\n\n\000\n")
                @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data, :on_error]
                @server.params[:error].message.should == "Subscription not found"
                @server.params[:data].should == "ERROR\ncontent-length:59\ncontent-type:text/plain\nmessage:Subscription not found\n" +
                                                "\nFailed frame:\n-----\nUNSUBSCRIBE\ndestination:/queue2\n\n\n-----\000\n"
              end

              it "deletes subscription" do
                @server.instance_variable_get(:@subscribes).should == {"/queue" => {:id => "1", :ack => "client"}}
                @server.receive_data("UNSUBSCRIBE\ndestination:/queue\n\n\000\n")
                @server.instance_variable_get(:@subscribes).should == {}
              end

              it "report successful unsubscribe to user" do
                @server.receive_data("UNSUBSCRIBE\ndestination:/queue\n\n\000\n")
                @server.called.should == [:on_connect, :send_data, :on_subscribe, :on_unsubscribe]
                @server.params[:subscribe_id].should == "1"
                @server.params[:destination].should == "/queue"
              end

              it "sends receipt if requested" do
                @server.receive_data("UNSUBSCRIBE\nid:1\nreceipt:1\n\n\000\n")
                @server.called.should == [:on_connect, :send_data, :on_subscribe, :on_unsubscribe, :send_data]
                @server.params[:data].should == "RECEIPT\nreceipt-id:1\n\n\000\n"
              end
            else
              it "raises ProtocolError if missing id header" do
                @server.receive_data("UNSUBSCRIBE\n\n\000\n")
                @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data, :on_error]
                @server.params[:error].message.should == "Missing 'id' header"
                @server.params[:data].should == "ERROR\ncontent-length:39\ncontent-type:text/plain\nmessage:Missing 'id' header\n" +
                                                "\nFailed frame:\n-----\nUNSUBSCRIBE\n\n\n-----\000\n"
              end

              it "raises ProtocolError if subscription not found" do
                @server.receive_data("UNSUBSCRIBE\nid:2\n\n\000\n")
                @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data, :on_error]
                @server.params[:error].message.should == "Subscription not found"
                @server.params[:data].should == "ERROR\ncontent-length:44\ncontent-type:text/plain\nmessage:Subscription not found\n" +
                                                "\nFailed frame:\n-----\nUNSUBSCRIBE\nid:2\n\n\n-----\000\n"
              end

              it "deletes subscription" do
                @server.instance_variable_get(:@subscribes).should == {"/queue" => {:id => "1", :ack => "client"}}
                @server.receive_data("UNSUBSCRIBE\nid:1\n\n\000\n")
                @server.instance_variable_get(:@subscribes).should == {}
              end

              it "report successful unsubscribe to user" do
                @server.receive_data("UNSUBSCRIBE\nid:1\n\n\000\n")
                @server.called.should == [:on_connect, :send_data, :on_subscribe, :on_unsubscribe]
                @server.params[:subscribe_id].should == "1"
                @server.params[:destination].should == "/queue"
              end

              it "sends receipt if requested" do
                @server.receive_data("UNSUBSCRIBE\nid:1\nreceipt:1\n\n\000\n")
                @server.called.should == [:on_connect, :send_data, :on_subscribe, :on_unsubscribe, :send_data]
                @server.params[:data].should == "RECEIPT\nreceipt-id:1\n\n\000\n"
              end
            end
          end

          it "raises ProtocolError if not connected" do
            @server.receive_data("UNSUBSCRIBE\n\n\000\n")
            @server.called.should == [:send_data, :on_error]
            @server.params[:error].message.should == "Not connected"
            @server.params[:data].should == "ERROR\ncontent-length:39\ncontent-type:text/plain\nmessage:Not connected\n" +
                                            "\nFailed frame:\n-----\nUNSUBSCRIBE\n\n\n-----\000\n"
          end
        end

        context :receive_ack do
          context "when connected" do
            before(:each) do
              @server.receive_data("CONNECT#{accept_version}\nhost:stomp\n\n\000\n")
              @server.receive_data("SUBSCRIBE\nack:client\ndestination:/queue\nid:1\n\n\000\n")
            end

            if version < "1.2"
              it "raises ProtocolError if missing message-id header" do
                @server.receive_data("ACK\n\n\000\n")
                @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data, :on_error]
                @server.params[:error].message.should == "Missing 'message-id' header"
                @server.params[:data].should == "ERROR\ncontent-length:31\ncontent-type:text/plain\nmessage:Missing 'message-id' header\n" +
                                                "\nFailed frame:\n-----\nACK\n\n\n-----\000\n"
              end

              if version == "1.0"
                it "reports ack to user" do
                  @server.message({"destination" => "/queue", "message-id" => "123"}, "hello")
                  @server.receive_data("ACK\nmessage-id:123\n\n\000\n")
                  @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data, :on_ack]
                  @server.params[:ack_id].should == "1"
                end

                it "sends receipt if requested" do
                  @server.message({"destination" => "/queue", "message-id" => "123"}, "hello")
                  @server.receive_data("ACK\nmessage-id:123\nreceipt:1\n\n\000\n")
                  @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data, :on_ack, :send_data]
                  @server.params[:data].should == "RECEIPT\nreceipt-id:1\n\n\000\n"
                end
              else
                it "reports ack to user" do
                  @server.message({"destination" => "/queue", "message-id" => "123", "subscription" => "1"}, "hello")
                  @server.receive_data("ACK\nmessage-id:123\n\n\000\n")
                  @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data, :on_ack]
                  @server.params[:ack_id].should == "1"
                end

                it "sends receipt if requested" do
                  @server.message({"destination" => "/queue", "message-id" => "123", "subscription" => "1"}, "hello")
                  @server.receive_data("ACK\nmessage-id:123\nreceipt:1\n\n\000\n")
                  @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data, :on_ack, :send_data]
                  @server.params[:data].should == "RECEIPT\nreceipt-id:1\n\n\000\n"
                end
              end
            else
              it "raises ProtocolError if missing id header" do
                @server.receive_data("ACK\n\n\000\n")
                @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data, :on_error]
                @server.params[:error].message.should == "Missing 'id' header"
                @server.params[:data].should == "ERROR\ncontent-length:31\ncontent-type:text/plain\nmessage:Missing 'id' header\n" +
                                                "\nFailed frame:\n-----\nACK\n\n\n-----\000\n"
              end

              it "reports ack to user" do
                @server.message({"destination" => "/queue", "message-id" => "123", "ack" => "1", "subscription" => "1"}, "hello")
                @server.receive_data("ACK\nid:1\n\n\000\n")
                @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data, :on_ack]
                @server.params[:ack_id].should == "1"
              end

              it "sends receipt if requested" do
                @server.message({"destination" => "/queue", "message-id" => "123", "ack" => "1", "subscription" => "1"}, "hello")
                @server.receive_data("ACK\nid:1\nreceipt:1\n\n\000\n")
                @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data, :on_ack, :send_data]
                @server.params[:data].should == "RECEIPT\nreceipt-id:1\n\n\000\n"
              end
            end
          end

          it "raises ProtocolError if not connected" do
            @server.receive_data("ACK\n\n\000\n")
            @server.called.should == [:send_data, :on_error]
            @server.params[:error].message.should == "Not connected"
            @server.params[:data].should == "ERROR\ncontent-length:31\ncontent-type:text/plain\nmessage:Not connected\n" +
                                            "\nFailed frame:\n-----\nACK\n\n\n-----\000\n"
          end
        end

        context :receive_nack do
          context "when connected" do
            before(:each) do
              @server.receive_data("CONNECT#{accept_version}\nhost:stomp\n\n\000\n")
              @server.receive_data("SUBSCRIBE\nack:client\ndestination:/queue\nid:1\n\n\000\n")
            end

            if version == "1.0"
              it "raises ProtocolError if nack not supported" do
                @server.receive_data("NACK\n\n\000\n")
                @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data, :on_error]
                @server.params[:error].message.should == "Invalid command"
                @server.params[:data].should == "ERROR\ncontent-length:32\ncontent-type:text/plain\nmessage:Invalid command\n" +
                                                "\nFailed frame:\n-----\nNACK\n\n\n-----\000\n"
              end
            elsif version == "1.1"
              it "raises ProtocolError if missing message-id header" do
                @server.receive_data("NACK\n\n\000\n")
                @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data, :on_error]
                @server.params[:error].message.should == "Missing 'message-id' header"
                @server.params[:data].should == "ERROR\ncontent-length:32\ncontent-type:text/plain\nmessage:Missing 'message-id' header\n" +
                                                "\nFailed frame:\n-----\nNACK\n\n\n-----\000\n"
              end

              it "reports nack to user" do
                @server.message({"destination" => "/queue", "message-id" => "123", "subscription" => "1"}, "hello")
                @server.receive_data("NACK\nmessage-id:123\n\n\000\n")
                @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data, :on_nack]
                @server.params[:ack_id].should == "1"
              end

              it "sends receipt if requested" do
                @server.message({"destination" => "/queue", "message-id" => "123", "subscription" => "1"}, "hello")
                @server.receive_data("NACK\nmessage-id:123\nreceipt:1\n\n\000\n")
                @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data, :on_nack, :send_data]
                @server.params[:data].should == "RECEIPT\nreceipt-id:1\n\n\000\n"
              end
            else
              it "raises ProtocolError if missing id header" do
                @server.receive_data("NACK\n\n\000\n")
                @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data, :on_error]
                @server.params[:error].message.should == "Missing 'id' header"
                @server.params[:data].should == "ERROR\ncontent-length:32\ncontent-type:text/plain\nmessage:Missing 'id' header\n" +
                                                "\nFailed frame:\n-----\nNACK\n\n\n-----\000\n"
              end

              it "reports nack to user" do
                @server.message({"destination" => "/queue", "message-id" => "123", "ack" => "1", "subscription" => "1"}, "hello")
                @server.receive_data("NACK\nid:1\n\n\000\n")
                @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data, :on_nack]
                @server.params[:ack_id].should == "1"
              end

              it "sends receipt if requested" do
                @server.message({"destination" => "/queue", "message-id" => "123", "ack" => "1", "subscription" => "1"}, "hello")
                @server.receive_data("NACK\nid:1\nreceipt:1\n\n\000\n")
                @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data, :on_nack, :send_data]
                @server.params[:data].should == "RECEIPT\nreceipt-id:1\n\n\000\n"
              end
            end
          end

          it "raises ProtocolError if not connected" do
            @server.receive_data("NACK\n\n\000\n")
            @server.called.should == [:send_data, :on_error]
            @server.params[:error].message.should == "Not connected"
            @server.params[:data].should == "ERROR\ncontent-length:32\ncontent-type:text/plain\nmessage:Not connected\n" +
                                            "\nFailed frame:\n-----\nNACK\n\n\n-----\000\n"
          end
        end

        context :receive_begin do
          context "when connected" do
            before(:each) do
              @server.receive_data("CONNECT#{accept_version}\nhost:stomp\n\n\000\n")
              @server.receive_data("SUBSCRIBE\nack:client\ndestination:/queue\nid:1\n\n\000\n")
            end

            it "raises ProtocolError if missing transaction header" do
              @server.receive_data("BEGIN\n\n\000\n")
              @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data, :on_error]
              @server.params[:error].message.should == "Missing 'transaction' header"
              @server.params[:data].should == "ERROR\ncontent-length:33\ncontent-type:text/plain\nmessage:Missing 'transaction' header\n" +
                                              "\nFailed frame:\n-----\nBEGIN\n\n\n-----\000\n"
            end

            it "raises ProtocolError if transaction already exists" do
              @server.receive_data("BEGIN\ntransaction:1\n\n\000\n")
              @server.receive_data("BEGIN\ntransaction:1\n\n\000\n")
              @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data, :on_error]
              @server.params[:error].message.should == "Transaction already exists"
              @server.params[:data].should == "ERROR\ncontent-length:47\ncontent-type:text/plain\nmessage:Transaction already exists\n" +
                                              "\nFailed frame:\n-----\nBEGIN\ntransaction:1\n\n\n-----\000\n"
            end

            it "records start of transaction" do
              @server.receive_data("BEGIN\ntransaction:1\n\n\000\n")
              @server.instance_variable_get(:@transactions).should == {"1" => []}
            end

            it "sends receipt if requested" do
              @server.receive_data("BEGIN\nreceipt:1\ntransaction:1\n\n\000\n")
              @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data]
              @server.params[:data].should == "RECEIPT\nreceipt-id:1\n\n\000\n"
            end
          end

          it "raises ProtocolError if not connected" do
            @server.receive_data("BEGIN\n\n\000\n")
            @server.called.should == [:send_data, :on_error]
            @server.params[:error].message.should == "Not connected"
            @server.params[:data].should == "ERROR\ncontent-length:33\ncontent-type:text/plain\nmessage:Not connected\n" +
                                            "\nFailed frame:\n-----\nBEGIN\n\n\n-----\000\n"
          end
        end

        context :receive_commit do
          context "when connected" do
            before(:each) do
              @server.receive_data("CONNECT#{accept_version}\nhost:stomp\n\n\000\n")
              @server.receive_data("SUBSCRIBE\nack:client\ndestination:/queue\nid:1\n\n\000\n")
            end

            it "raises ProtocolError if missing transaction header" do
              @server.receive_data("COMMIT\n\n\000\n")
              @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data, :on_error]
              @server.params[:error].message.should == "Missing 'transaction' header"
              @server.params[:data].should == "ERROR\ncontent-length:34\ncontent-type:text/plain\nmessage:Missing 'transaction' header\n" +
                                              "\nFailed frame:\n-----\nCOMMIT\n\n\n-----\000\n"
            end

            it "raises ProtocolError if transaction not found" do
              @server.receive_data("COMMIT\ntransaction:1\n\n\000\n")
              @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data, :on_error]
              @server.params[:error].message.should == "Transaction not found"
              @server.params[:data].should == "ERROR\ncontent-length:48\ncontent-type:text/plain\nmessage:Transaction not found\n" +
                                              "\nFailed frame:\n-----\nCOMMIT\ntransaction:1\n\n\n-----\000\n"
            end

            it "processes frames in transaction and deletes it" do
              @server.receive_data("BEGIN\ntransaction:1\n\n\000\n")
              @server.receive_data("SEND\ndestination:/queue\ntransaction:1\n\nhello\000\n")
              @server.receive_data("SEND\ndestination:/queue\ntransaction:1\n\nbye\000\n")
              @server.instance_variable_get(:@transactions)["1"].size.should == 2
              @server.receive_data("COMMIT\ntransaction:1\n\n\000\n")
              @server.instance_variable_get(:@transactions).should == {}
              @server.called.should == [:on_connect, :send_data, :on_subscribe, :on_message, :on_message]
            end

            it "sends receipt if requested" do
              @server.receive_data("BEGIN\ntransaction:1\n\n\000\n")
              @server.receive_data("COMMIT\nreceipt:1\ntransaction:1\n\n\000\n")
              @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data]
              @server.params[:data].should == "RECEIPT\nreceipt-id:1\n\n\000\n"
            end
          end

          it "raises ProtocolError if not connected" do
            @server.receive_data("COMMIT\n\n\000\n")
            @server.called.should == [:send_data, :on_error]
            @server.params[:error].message.should == "Not connected"
            @server.params[:data].should == "ERROR\ncontent-length:34\ncontent-type:text/plain\nmessage:Not connected\n" +
                                            "\nFailed frame:\n-----\nCOMMIT\n\n\n-----\000\n"
          end
        end

        context :receive_abort do
          context "when connected" do
            before(:each) do
              @server.receive_data("CONNECT#{accept_version}\nhost:stomp\n\n\000\n")
              @server.receive_data("SUBSCRIBE\nack:client\ndestination:/queue\nid:1\n\n\000\n")
            end

            it "raises ProtocolError if missing transaction header" do
              @server.receive_data("ABORT\n\n\000\n")
              @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data, :on_error]
              @server.params[:error].message.should == "Missing 'transaction' header"
              @server.params[:data].should == "ERROR\ncontent-length:33\ncontent-type:text/plain\nmessage:Missing 'transaction' header\n" +
                                              "\nFailed frame:\n-----\nABORT\n\n\n-----\000\n"
            end

            it "raises ProtocolError if transaction not found" do
              @server.receive_data("ABORT\ntransaction:1\n\n\000\n")
              @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data, :on_error]
              @server.params[:error].message.should == "Transaction not found"
              @server.params[:data].should == "ERROR\ncontent-length:47\ncontent-type:text/plain\nmessage:Transaction not found\n" +
                                              "\nFailed frame:\n-----\nABORT\ntransaction:1\n\n\n-----\000\n"
            end

            it "deletes transaction" do
              @server.receive_data("BEGIN\ntransaction:1\n\n\000\n")
              @server.receive_data("SEND\ndestination:/queue\ntransaction:1\n\nhello\000\n")
              @server.receive_data("SEND\ndestination:/queue\ntransaction:1\n\nbye\000\n")
              @server.instance_variable_get(:@transactions)["1"].size.should == 2
              @server.receive_data("ABORT\ntransaction:1\n\n\000\n")
              @server.instance_variable_get(:@transactions).should == {}
              @server.called.should == [:on_connect, :send_data, :on_subscribe]
            end

            it "sends receipt if requested" do
              @server.receive_data("BEGIN\ntransaction:1\n\n\000\n")
              @server.receive_data("ABORT\nreceipt:1\ntransaction:1\n\n\000\n")
              @server.called.should == [:on_connect, :send_data, :on_subscribe, :send_data]
              @server.params[:data].should == "RECEIPT\nreceipt-id:1\n\n\000\n"
            end
          end

          it "raises ProtocolError if not connected" do
            @server.receive_data("ABORT\n\n\000\n")
            @server.called.should == [:send_data, :on_error]
            @server.params[:error].message.should == "Not connected"
            @server.params[:data].should == "ERROR\ncontent-length:33\ncontent-type:text/plain\nmessage:Not connected\n" +
                                            "\nFailed frame:\n-----\nABORT\n\n\n-----\000\n"
          end
        end

        context :receive_disconnect do
          context "when connected" do
            before(:each) do
              @server.receive_data("CONNECT#{accept_version}\nhost:stomp\n\n\000\n")
            end

            it "reports disconnect to user" do
              @server.receive_data("DISCONNECT\n\n\000\n")
              @server.called.should == [:on_connect, :send_data, :on_disconnect]
              @server.params[:frame].command.should == "DISCONNECT"
              @server.params[:reason].should == "client request"
            end

            it "sends receipt if requested" do
              @server.receive_data("BEGIN\ntransaction:1\n\n\000\n")
              @server.receive_data("DISCONNECT\nreceipt:1\n\n\000\n")
              @server.called.should == [:on_connect, :send_data, :on_disconnect, :send_data]
              @server.params[:data].should == "RECEIPT\nreceipt-id:1\n\n\000\n"
            end
          end

          it "raises ProtocolError if not connected" do
            @server.receive_data("DISCONNECT\n\n\000\n")
            @server.called.should == [:send_data, :on_error]
            @server.params[:error].message.should == "Not connected"
            @server.params[:data].should == "ERROR\ncontent-length:38\ncontent-type:text/plain\nmessage:Not connected\n" +
                                            "\nFailed frame:\n-----\nDISCONNECT\n\n\n-----\000\n"
          end
        end
      end
    end
  end

  context "support functions" do
    context :process_frame do
      it "sends frame to receive function for processing" do
        frame = StompOut::Frame.new("CONNECT", {"accept-version" => "1.0,1.1,1.2", "host" => "stomp"})
        @server.send(:process_frame, frame).should be true
        @server.called.should == [:on_connect, :send_data]
      end

      it "adds request to transaction if frame has transaction header" do
        @server.receive_data("CONNECT\naccept-version:1.0,1.1,1.2\nhost:stomp\n\n\000\n")
        @server.receive_data("SUBSCRIBE\nack:client\ndestination:/queue\nid:1\n\n\000\n")
        @server.receive_data("BEGIN\ntransaction:1\n\n\000\n")
        @server.send(:process_frame, StompOut::Frame.new("SEND", {"destination" => "/queue", "transaction" => "1"}))
        @server.send(:process_frame, StompOut::Frame.new("NACK", {"id" => "1", "transaction" => "1"}))
        @server.send(:process_frame, StompOut::Frame.new("ACK", {"id" => "2", "transaction" => "1"}))
        @server.instance_variable_get(:@transactions)["1"].size.should == 3
      end

      (StompOut::Server::CLIENT_COMMANDS - StompOut::Server::TRANSACTIONAL_COMMANDS).each do |command|
        it "raises ProtocolError if transaction used with #{command.to_s.upcase} command" do
          @server.receive_data("CONNECT\naccept-version:1.0,1.1,1.2\nhost:stomp\n\n\000\n")
          @server.receive_data("SUBSCRIBE\nack:client\ndestination:/queue\nid:1\n\n\000\n")
          @server.receive_data("BEGIN\ntransaction:1\n\n\000\n")
          lambda do
            @server.send(:process_frame, StompOut::Frame.new(command.to_s.upcase, {"transaction" => "1"}))
          end.should raise_error(StompOut::ProtocolError, "Transaction not permitted")
        end
      end

      it "raises ProtocolError if not connected" do
        lambda do
          @server.send(:process_frame, StompOut::Frame.new("SUBSCRIBE"))
        end.should raise_error(StompOut::ProtocolError, "Not connected")
      end

      it "raises ProtocolError if it is not a recognized command" do
        lambda do
          @server.send(:process_frame, StompOut::Frame.new("BOGUS"))
        end.should raise_error(StompOut::ProtocolError, "Unhandled frame: BOGUS")
      end
    end

    context :send_frame do
      context "when connected" do
        before(:each) do
          @server.receive_data("CONNECT\naccept-version:1.0,1.1,1.2\nhost:stomp\n\n\000\n")
        end

        it "sends frame to client" do
          headers = {"destination" => "/queue", "message-id" => "123", "subscription" => "1"}
          frame = @server.send(:send_frame, "MESSAGE", headers)
          frame.command.should == "MESSAGE"
          frame.headers.should == headers
          frame.body.should == ""
          @server.called.should == [:on_connect, :send_data, :send_data]
          @server.params[:data].should == "MESSAGE\ndestination:/queue\nmessage-id:123\nsubscription:1\n\n\000\n"
        end

        it "adds content-length and content-type to headers if there is a body" do
          headers = {"destination" => "/queue", "message-id" => "123", "subscription" => "1"}
          frame = @server.send(:send_frame, "MESSAGE", headers, "hello")
          frame.command.should == "MESSAGE"
          frame.headers.should == headers.merge("content-length" => "5", "content-type" => "text/plain")
          frame.body.should == "hello"
          @server.called.should == [:on_connect, :send_data, :send_data]
          @server.params[:data].should == "MESSAGE\ncontent-length:5\ncontent-type:text/plain\ndestination:/queue\nmessage-id:123" +
                                          "\nsubscription:1\n\nhello\000\n"
        end
      end

      it "notifies heartbeat" do
        @server.receive_data("CONNECT\naccept-version:1.0,1.1,1.2\nheart-beat:0,0\nhost:stomp\n\n\000\n")
        @server.heartbeat.instance_variable_get(:@sent_data).should be true
      end

      context "when not connected" do
        it "sends ERROR frame without being connected" do
          @server.send(:send_frame, "ERROR", {"message" => "Failed"})
          @server.called.should == [:send_data]
          @server.params[:data].should == "ERROR\nmessage:Failed\n\n\000\n"
        end

        it "raises ProtocolError if not connected and command is not ERROR" do
          lambda do
            @server.send(:send_frame, "MESSAGE")
          end.should raise_error(StompOut::ProtocolError, "Not connected")
        end
      end
    end

    context :handle_transaction do
      before(:each) do
        @server.receive_data("CONNECT\naccept-version:1.0,1.1,1.2\nhost:stomp\n\n\000\n")
      end

      [:begin, :commit, :abort].each do |command|
        it "receives and processes #{command.to_s.upcase} command" do
          frame = StompOut::Frame.new(command.to_s.upcase, {"transaction" => "1"})
          flexmock(@server).should_receive(("receive_" + command.to_s).to_sym).with(frame).once
          @server.send(:handle_transaction, frame, "1", command).should be true
        end
      end

      [:send, :ack, :nack].each do |command|
        it "adds #{command.to_s.upcase} command to transaction" do
          @server.send(:handle_transaction, StompOut::Frame.new("BEGIN", {"transaction" => "1"}), "1", :begin)
          frame = StompOut::Frame.new(command.to_s.upcase, {"transaction" => "1"})
          @server.send(:handle_transaction, frame, "1", command).should be true
          @server.instance_variable_get(:@transactions).should == {"1" => [frame]}
        end

        it "raises ProtocolError if transaction not found" do
          @server.send(:handle_transaction, StompOut::Frame.new("BEGIN", {"transaction" => "1"}), "1", :begin)
          frame = StompOut::Frame.new(command.to_s.upcase, {"transaction" => "2"})
          lambda do
            @server.send(:handle_transaction, frame, "2", command).should be true
          end.should raise_error(StompOut::ProtocolError, "Transaction not found")
        end
      end
    end

    context :negotiate_version do
      it "chooses version 1.0 if none specified by client" do
        frame = StompOut::Frame.new("CONNECT", {"host" => "stomp"})
        @server.send(:negotiate_version, frame).should == "1.0"
      end

      SERVER_SUPPORTED_VERSIONS.size.times do |i|
        [SERVER_SUPPORTED_VERSIONS[0..i].join(","), SERVER_SUPPORTED_VERSIONS[i..-1].join(",")].each do |versions|
          if versions != "1.0"
            context "when client supports #{versions}" do
              version = versions.split(",").last
              it "chooses highest version in common which is #{version}" do
                frame = StompOut::Frame.new("CONNECT", {"accept-version" => versions, "host" => "stomp"})
                @server.send(:negotiate_version, frame).should == version
              end
            end
          end
        end
      end

      it "raises ProtocolError if there is no compatible version" do
        frame = StompOut::Frame.new("CONNECT", {"accept-version" => "1.3", "host" => "stomp"})
        lambda do
          @server.send(:negotiate_version, frame).should == version
        end.should raise_error(StompOut::ProtocolError, "Incompatible version")
      end
    end
  end
end
