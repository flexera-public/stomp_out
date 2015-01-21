require 'spec_helper'
require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'stomp_out', 'client_user')

describe StompOut::Client do

  CLIENT_SUPPORTED_VERSIONS = StompOut::Client::SUPPORTED_VERSIONS

  before(:each) do
    @options = {}
    @user = StompOut::ClientUser.new
    @client = StompOut::Client.new(@user, @options)
  end

  context :initialize do
    it "initializes attributes and with virtual host defaulting 'stomp'" do
      @client.host.should == "stomp"
      @client.connected.should == false
      @client.version.should be nil
      @client.session_id.should be nil
      @client.server_name.should be nil
      @client.heartbeat.should be nil
    end

    it "sets virtual host if specified" do
      @client = StompOut::Client.new(@user, @options.merge(:host => "vhost"))
      @client.host.should == "vhost"
    end

    it "enables receipts if specified" do
      @client = StompOut::Client.new(@user, @options.merge(:receipt => true))
      @client.instance_variable_get(:@receipt).should be true
    end
  end

  context :subscriptions do
    it "lists subscription destinations" do
      @client.instance_variable_set(:@connected, true)
      @client.subscribe("/queue")
      @client.subscriptions.should == ["/queue"]
    end
  end

  context :transactions do
    it "lists active transaction IDs" do
      @client.instance_variable_set(:@connected, true)
      @client.begin
      @client.transactions.should == ["1"]
    end
  end

  context :receive_data do
    it "processes frame data" do
      @client.receive_data("ERROR\nmessage:failed\n\n\000").should be true
      @user.called.should == [:on_error]
      @user.frame.command.should == "ERROR"
      @user.error.should == "failed"
    end

    it "notifies heartbeat" do
      @client.receive_data("CONNECTED\nversion:1.2\nheart-beat:0,0\n\n\000").should be true
      @client.heartbeat.instance_variable_get(:@received_data).should be true
    end

    it "reports error" do
      @client.receive_data("RECEIPT\n\n\000").should be true
      @user.called.should == [:on_error]
      @user.error.should == "Missing 'receipt-id' header"
    end
  end

  context :send_data do
    it "passes data to user" do
      @client.send_data("ACK\nack:1\n\n\000").should be true
      @user.called.should == [:send_data]
      @user.data.should == "ACK\nack:1\n\n\000"
    end

    it "notifies heartbeat" do
      @client.receive_data("CONNECTED\nversion:1.2\nheart-beat:0,0\n\n\000")
      @client.send_data("ACK\nack:1\n\n\000").should be true
      @client.heartbeat.instance_variable_get(:@sent_data).should be true
    end
  end

  context :report_error do
    [StompOut::ProtocolError, StompOut::ApplicationError].each do |error|
      it "reports error message for #{error.class}" do
        @client.report_error(error.new("failed"))
        @user.called.should == [:on_error]
        @user.error.should == "failed"
      end
    end

    it "reports error message for ApplicationError" do
      @client.report_error(StompOut::ApplicationError.new("failed"))
      @user.called.should == [:on_error]
      @user.error.should == "failed"
    end

    it "reports error class, message, and backtrace for unexpected exceptions" do
      begin
        nil + 1
      rescue StandardError => error
        @client.report_error(error)
        @user.called.should == [:on_error]
        @user.error.should == "NoMethodError: undefined method `+' for nil:NilClass"
        @user.details.should =~ /client_spec.rb/
      end
    end

    it "reports error string for any other types of errors" do
      @client.report_error("failed")
      @user.called.should == [:on_error]
      @user.error.should == "failed"
    end
  end

  context "client commands" do

    context :connect do
      it "sends CONNECT frame to server" do
        @client.connect.should be true
        @user.called.should == [:send_data]
        @user.data.should == "CONNECT\naccept-version:1.0,1.1,1.2\nhost:stomp\n\n\000\n"
      end

      it "includes application specific headers" do
        @client.connect(nil, nil, nil, {"other" => "header"}).should be true
        @user.called.should == [:send_data]
        @user.data.should == "CONNECT\naccept-version:1.0,1.1,1.2\nhost:stomp\nother:header\n\n\000\n"
      end

      it "configures heartbeat if specified" do
        @client.connect(10000).should be true
        @user.called.should == [:send_data]
        @user.data.should == "CONNECT\naccept-version:1.0,1.1,1.2\nheart-beat:5000,10000\nhost:stomp\n\n\000\n"
      end

      it "adds authentication headers if specified" do
        @client.connect(nil, "me", "secret").should be true
        @user.called.should == [:send_data]
        @user.data.should == "CONNECT\naccept-version:1.0,1.1,1.2\nhost:stomp\nlogin:me\npasscode:secret\n\n\000\n"
      end

      it "raises ProtocolError if already connected" do
        @client.receive_data("CONNECTED\nversion:1.2\nheart-beat:0,0\n\n\000")
        lambda do
          @client.connect
        end.should raise_error(StompOut::ProtocolError, "Already connected")
      end

      it "raises ApplicationError if heartbeat is not usable" do
        flexmock(StompOut::Heartbeat).should_receive(:usable?).and_return(false).once
        lambda do
          @client.connect(1000)
        end.should raise_error(StompOut::ApplicationError, "Heartbeat not usable without eventmachine")
      end
    end

    CLIENT_SUPPORTED_VERSIONS.each do |version|
      context version do
        context :message do
          context "when connected" do
            before(:each) do
              @client.receive_data("CONNECTED\nversion:#{version}\n\n\000")
            end

            it "sends SEND frame to server" do
              @client.message("/queue", "hello").should be nil
              @user.called.should == [:on_connected, :send_data]
              @user.data.should == "SEND\ncontent-length:5\ncontent-type:text/plain\ndestination:/queue\n\nhello\000\n"
            end

            it "includes application specific headers" do
              @client.message("/queue", "hello", nil, nil, nil, {"other" => "header"}).should be nil
              @user.called.should == [:on_connected, :send_data]
              @user.data.should == "SEND\ncontent-length:5\ncontent-type:text/plain\ndestination:/queue\nother:header\n\nhello\000\n"
            end

            it "uses specified content-type" do
              @client.message("/queue", "{\"some\":\"data\"}", "application/json").should be nil
              @user.called.should == [:on_connected, :send_data]
              @user.data.should == "SEND\ncontent-length:15\ncontent-type:application/json\ndestination:/queue\n\n{\"some\":\"data\"}\000\n"
            end

            it "JSON-encodes body if content-type is application/json and :auto_json enabled" do
              @user = StompOut::ClientUser.new
              @client = StompOut::Client.new(@user, @options.merge(:auto_json => true))
              @client.receive_data("CONNECTED\nversion:#{version}\n\n\000")
              @client.message("/queue", {:some => "data"}, "application/json").should be nil
              @user.called.should == [:on_connected, :send_data]
              @user.data.should == "SEND\ncontent-length:15\ncontent-type:application/json\ndestination:/queue\n\n{\"some\":\"data\"}\000\n"
            end

            it "adds request to transaction if transaction ID specified" do
              transaction_id, _ = @client.begin
              @client.message("/queue", nil, nil, nil, transaction_id).should be nil
              @user.called.should == [:on_connected, :send_data, :send_data]
              @user.data.should == "SEND\ndestination:/queue\ntransaction:1\n\n\000\n"
            end

            it "returns receipt-id if enabled globally" do
              @client = StompOut::Client.new(@user, @options.merge(:receipt => true))
              @client.receive_data("CONNECTED\nversion:#{version}\n\n\000")
              @client.message("/queue", "hello").should == "1"
            end

            it "returns receipt-id if enabled locally" do
              @client.message("/queue", "hello", nil, true).should == "1"
            end
          end

          it "raises ProtocolError if not connected" do
            lambda do
              @client.message("/queue", {}, "")
            end.should raise_error(StompOut::ProtocolError, "Not connected")
          end
        end

        context :subscribe do
          context "when connected" do
            before(:each) do
              @client.receive_data("CONNECTED\nversion:#{version}\n\n\000")
            end

            it "sends SUBSCRIBE frame to server" do
              @client.subscribe("/queue")
              @user.called.should == [:on_connected, :send_data]
              @user.data.should == "SUBSCRIBE\ndestination:/queue\nid:1\n\n\000\n"
            end

            it "includes application specific headers" do
              @client.subscribe("/queue", nil, nil, {"other" => "header"}).should be nil
              @user.called.should == [:on_connected, :send_data]
              @user.data.should == "SUBSCRIBE\ndestination:/queue\nid:1\nother:header\n\n\000\n"
            end

            it "creates subscription ID and adds subscription to list" do
              @client.instance_variable_get(:@subscriptions).should == {}
              @client.subscribe("/queue")
              @client.instance_variable_get(:@subscriptions).should == {"/queue" => {:ack => nil, :id => "1"}}
            end

            it "uses given ack setting" do
              @client.subscribe("/queue", "client")
              @user.data.should == "SUBSCRIBE\nack:client\ndestination:/queue\nid:1\n\n\000\n"
            end

            it "returns receipt-id if enabled globally" do
              @client = StompOut::Client.new(@user, @options.merge(:receipt => true))
              @client.receive_data("CONNECTED\nversion:#{version}\n\n\000")
              @client.subscribe("/queue").should == "1"
            end

            it "returns receipt-id if enabled locally" do
              @client.subscribe("/queue", nil, true).should == "1"
            end

            it "raises ProtocolError if the ack setting is invalid" do
              lambda do
                @client.subscribe("/queue", "bogus")
              end.should raise_error(StompOut::ProtocolError, "Invalid 'ack' setting")
            end

            it "raises ApplicationError if already subscribed to the given destination" do
              @client.subscribe("/queue")
              lambda do
                @client.subscribe("/queue")
              end.should raise_error(StompOut::ApplicationError, "Already subscribed to '/queue'")
            end
          end

          it "raises ProtocolError if not connected" do
            lambda do
              @client.subscribe("/queue", "bogus")
            end.should raise_error(StompOut::ProtocolError, "Not connected")
          end
        end

        context :unsubscribe do
          context "when connected" do
            before(:each) do
              @client.receive_data("CONNECTED\nversion:#{version}\n\n\000")
            end

            if version == "1.0"
              it "sends UNSUBSCRIBE frame to server" do
                @client.subscribe("/queue")
                @client.unsubscribe("/queue")
                @user.called.should == [:on_connected, :send_data, :send_data]
                @user.data.should == "UNSUBSCRIBE\ndestination:/queue\nid:1\n\n\000\n"
              end

              it "includes application specific headers" do
                @client.subscribe("/queue")
                @client.unsubscribe("/queue", nil, {"other" => "header"})
                @user.called.should == [:on_connected, :send_data, :send_data]
                @user.data.should == "UNSUBSCRIBE\ndestination:/queue\nid:1\nother:header\n\n\000\n"
              end
            else
              it "sends UNSUBSCRIBE frame to server" do
                @client.subscribe("/queue")
                @client.unsubscribe("/queue")
                @user.called.should == [:on_connected, :send_data, :send_data]
                @user.data.should == "UNSUBSCRIBE\nid:1\n\n\000\n"
              end

              it "includes application specific headers" do
                @client.subscribe("/queue")
                @client.unsubscribe("/queue", nil, {"other" => "header"})
                @user.called.should == [:on_connected, :send_data, :send_data]
                @user.data.should == "UNSUBSCRIBE\nid:1\nother:header\n\n\000\n"
              end
            end

            it "deletes the given subscription from list" do
              @client.instance_variable_get(:@subscriptions).should == {}
              @client.subscribe("/queue")
              @client.instance_variable_get(:@subscriptions).should == {"/queue" => {:ack => nil, :id => "1"}}
              @client.unsubscribe("/queue")
              @client.instance_variable_get(:@subscriptions).should == {}
            end

            it "returns receipt-id if enabled globally" do
              @client = StompOut::Client.new(@user, @options.merge(:receipt => true))
              @client.receive_data("CONNECTED\nversion:#{version}\n\n\000")
              @client.subscribe("/queue").should == "1"
              @client.unsubscribe("/queue").should == "2"
            end

            it "returns receipt-id if enabled locally" do
              @client.subscribe("/queue", nil, true).should == "1"
              @client.unsubscribe("/queue", true).should == "2"
            end

            it "raises ApplicationError if not subscribed to the given destination" do
              lambda do
                @client.unsubscribe("/queue")
              end.should raise_error(StompOut::ApplicationError, "Subscription to '/queue' not found")
            end
          end

          it "raises ProtocolError if not connected" do
            lambda do
              @client.unsubscribe("/queue")
            end.should raise_error(StompOut::ProtocolError, "Not connected")
          end
        end

        context :ack do
          context "when connected" do
            before(:each) do
              @client.receive_data("CONNECTED\nversion:#{version}\n\n\000")
              @client.subscribe("/queue")
            end

            if version == "1.0"
              before(:each) do
                @client.receive_data("MESSAGE\nack:9\ndestination:/queue\nmessage-id:123\n\nhello\000\n")
              end

              it "sends ACK frame to server" do
                @client.ack("9").should be nil
                @user.called.should == [:on_connected, :send_data, :on_message, :send_data]
                @user.data.should == "ACK\nmessage-id:123\n\n\000\n"
              end

              it "includes application specific headers" do
                @client.ack("9", nil, nil, {"other" => "header"}).should be nil
                @user.called.should == [:on_connected, :send_data, :on_message, :send_data]
                @user.data.should == "ACK\nmessage-id:123\nother:header\n\n\000\n"
              end

              it "adds request to transaction if transaction ID specified" do
                transaction_id, _ = @client.begin
                @client.ack("9", nil, transaction_id).should be nil
                @user.called.should == [:on_connected, :send_data, :on_message, :send_data, :send_data]
                @user.data.should == "ACK\nmessage-id:123\ntransaction:1\n\n\000\n"
              end

              it "returns receipt-id if enabled globally" do
                @client = StompOut::Client.new(@user, @options.merge(:receipt => true))
                @client.receive_data("CONNECTED\nversion:#{version}\n\n\000")
                @client.subscribe("/queue").should == "1"
                @client.receive_data("MESSAGE\nack:9\ndestination:/queue\nmessage-id:123\n\nhello\000\n")
                @client.ack("9").should == "2"
              end

              it "returns receipt-id if enabled locally" do
                @client.ack("9", true).should == "1"
              end

              it "raises ApplicationError if no message was received with given ack ID" do
                lambda do
                  @client.ack("8")
                end.should raise_error(StompOut::ApplicationError, "No message was received with ack 8")
              end
            else
              before(:each) do
                @client.receive_data("MESSAGE\nack:9\ndestination:/queue\nmessage-id:123\nsubscription:1\n\nhello\000\n")
              end

              it "sends ACK frame to server" do
                @client.ack("9").should be nil
                @user.called.should == [:on_connected, :send_data, :on_message, :send_data]
                @user.data.should == "ACK\nid:9\n\n\000\n"
              end

              it "includes application specific headers" do
                @client.ack("9", nil, nil, {"other" => "header"}).should be nil
                @user.called.should == [:on_connected, :send_data, :on_message, :send_data]
                @user.data.should == "ACK\nid:9\nother:header\n\n\000\n"
              end

              it "adds request to transaction if transaction ID specified" do
                transaction_id, _ = @client.begin
                @client.ack("9", nil, transaction_id).should be nil
                @user.called.should == [:on_connected, :send_data, :on_message, :send_data, :send_data]
                @user.data.should == "ACK\nid:9\ntransaction:1\n\n\000\n"
              end

              it "returns receipt-id if enabled globally" do
                @client = StompOut::Client.new(@user, @options.merge(:receipt => true))
                @client.receive_data("CONNECTED\nversion:#{version}\n\n\000")
                @client.subscribe("/queue").should == "1"
                @client.receive_data("MESSAGE\nack:9\ndestination:/queue\nmessage-id:123\nsubscription:1\n\nhello\000\n")
                @client.ack("9").should == "2"
              end

              it "returns receipt-id if enabled locally" do
                @client.ack("9", true).should == "1"
              end
            end

            it "deletes the associated message ID from list" do
              @client.instance_variable_get(:@message_ids).should == {"9" => "123"}
              @client.ack("9")
              @client.instance_variable_get(:@message_ids).should == {}
            end
          end

          it "raises ProtocolError if not connected" do
            lambda do
              @client.ack("9")
            end.should raise_error(StompOut::ProtocolError, "Not connected")
          end
        end

        context :nack do
          context "when connected" do
            before(:each) do
              @client.receive_data("CONNECTED\nversion:#{version}\n\n\000")
              @client.subscribe("/queue")
              @client.receive_data("MESSAGE\nack:9\ndestination:/queue\nmessage-id:123\nsubscription:1\n\nhello\000\n")
            end

            if version == "1.0"
              it "raises ProtocolError indicating not supported" do
                lambda do
                  @client.nack("9").should be nil
                end.should raise_error(StompOut::ProtocolError, "Command 'nack' not supported")
              end
            else
              it "sends NACK frame to server" do
                @client.nack("9").should be nil
                @user.called.should == [:on_connected, :send_data, :on_message, :send_data]
                @user.data.should == "NACK\nid:9\n\n\000\n"
              end

              it "includes application specific headers" do
                @client.nack("9", nil, nil, {"other" => "header"}).should be nil
                @user.called.should == [:on_connected, :send_data, :on_message, :send_data]
                @user.data.should == "NACK\nid:9\nother:header\n\n\000\n"
              end

              it "adds request to transaction if transaction ID specified" do
                transaction_id, _ = @client.begin
                @client.nack("9", nil, transaction_id).should be nil
                @user.called.should == [:on_connected, :send_data, :on_message, :send_data, :send_data]
                @user.data.should == "NACK\nid:9\ntransaction:1\n\n\000\n"
              end

              it "deletes the associated message ID from list" do
                @client.instance_variable_get(:@message_ids).should == {"9" => "123"}
                @client.nack("9").should be nil
                @client.instance_variable_get(:@message_ids).should == {}
              end

              it "returns receipt-id if enabled globally" do
                @client = StompOut::Client.new(@user, @options.merge(:receipt => true))
                @client.receive_data("CONNECTED\nversion:#{version}\n\n\000")
                @client.subscribe("/queue").should == "1"
                @client.receive_data("MESSAGE\nack:9\ndestination:/queue\nmessage-id:123\nsubscription:1\n\nhello\000\n")
                @client.nack("9").should == "2"
              end

              it "returns receipt-id if enabled locally" do
                @client.nack("9", true).should == "1"
              end
            end
          end

          it "raises ProtocolError if not connected" do
            lambda do
              @client.nack("9")
            end.should raise_error(StompOut::ProtocolError, "Not connected")
          end
        end

        context :begin do
          context "when connected" do
            before(:each) do
              @client.receive_data("CONNECTED\nversion:#{version}\n\n\000")
            end

            it "sends BEGIN frame to server" do
              @client.begin.should == ["1", nil]
              @user.called.should == [:on_connected, :send_data]
              @user.data.should == "BEGIN\ntransaction:1\n\n\000\n"
            end

            it "includes application specific headers" do
              @client.begin(nil, {"other" => "header"}).should == ["1", nil]
              @user.called.should == [:on_connected, :send_data]
              @user.data.should == "BEGIN\nother:header\ntransaction:1\n\n\000\n"
            end

            it "creates transaction ID and stores it in list" do
              @client.begin.should == ["1", nil]
              @client.instance_variable_get(:@transaction_ids).should == ["1"]
            end

            it "returns receipt-id if enabled globally" do
              @client = StompOut::Client.new(@user, @options.merge(:receipt => true))
              @client.receive_data("CONNECTED\nversion:#{version}\n\n\000")
              @client.begin.should == ["1", "1"]
            end

            it "returns receipt-id if enabled locally" do
              @client.begin(true).should == ["1", "1"]
            end
          end

          it "raises ProtocolError if not connected" do
            lambda do
              @client.begin
            end.should raise_error(StompOut::ProtocolError, "Not connected")
          end
        end

        context :commit do
          context "when connected" do
            before(:each) do
              @client.receive_data("CONNECTED\nversion:#{version}\n\n\000")
              @client.begin
            end

            it "sends COMMIT frame to server" do
              @client.commit("1").should be nil
              @user.called.should == [:on_connected, :send_data, :send_data]
              @user.data.should == "COMMIT\ntransaction:1\n\n\000\n"
            end

            it "includes application specific headers" do
              @client.commit("1", nil, {"other" => "header"}).should be nil
              @user.called.should == [:on_connected, :send_data, :send_data]
              @user.data.should == "COMMIT\nother:header\ntransaction:1\n\n\000\n"
            end

            it "returns receipt-id if enabled globally" do
              @client = StompOut::Client.new(@user, @options.merge(:receipt => true))
              @client.receive_data("CONNECTED\nversion:#{version}\n\n\000")
              @client.begin.should == ["1", "1"]
              @client.commit("1").should == "2"
            end

            it "returns receipt-id if enabled locally" do
              @client.commit("1", true).should == "1"
            end

            it "raises ApplicationError if no transaction with given ID exists" do
              lambda do
                @client.commit("2")
              end.should raise_error(StompOut::ApplicationError, "Transaction 2 not found")
            end
          end

          it "raises ProtocolError if not connected" do
            lambda do
              @client.commit("1")
            end.should raise_error(StompOut::ProtocolError, "Not connected")
          end
        end

        context :abort do
          context "when connected" do
            before(:each) do
              @client.receive_data("CONNECTED\nversion:#{version}\n\n\000")
              @client.begin
            end

            it "sends ABORT frame to server" do
              @client.abort("1").should be nil
              @user.called.should == [:on_connected, :send_data, :send_data]
              @user.data.should == "ABORT\ntransaction:1\n\n\000\n"
            end

            it "includes application specific headers" do
              @client.abort("1", nil, {"other" => "header"}).should be nil
              @user.called.should == [:on_connected, :send_data, :send_data]
              @user.data.should == "ABORT\nother:header\ntransaction:1\n\n\000\n"
            end

            it "returns receipt-id if enabled globally" do
              @client = StompOut::Client.new(@user, @options.merge(:receipt => true))
              @client.receive_data("CONNECTED\nversion:#{version}\n\n\000")
              @client.begin.should == ["1", "1"]
              @client.abort("1").should == "2"
            end

            it "returns receipt-id if enabled locally" do
              @client.abort("1", true).should == "1"
            end

            it "raises ApplicationError if no transaction with given ID exists" do
              lambda do
                @client.abort("2")
              end.should raise_error(StompOut::ApplicationError, "Transaction 2 not found")
            end
          end

          it "raises ProtocolError if not connected" do
            lambda do
              @client.abort("1")
            end.should raise_error(StompOut::ProtocolError, "Not connected")
          end
        end

        context :disconnect do
          context "when connected" do
            before(:each) do
              @client.receive_data("CONNECTED\nheart-beat:0,0\nversion:#{version}\n\n\000")
            end

            it "sends DISCONNECT frame to server" do
              @client.disconnect.should be nil
              @user.called.should == [:on_connected, :send_data]
              @user.data.should == "DISCONNECT\n\n\000\n"
              @client.connected.should be false
            end

            it "includes application specific headers" do
              @client.disconnect(nil, {"other" => "header"}).should be nil
              @user.called.should == [:on_connected, :send_data]
              @user.data.should == "DISCONNECT\nother:header\n\n\000\n"
            end

            it "stops heartbeat" do
              flexmock(@client.heartbeat).should_receive(:stop).once
              @client.disconnect.should be nil
            end

            it "returns receipt-id if enabled globally" do
              @client = StompOut::Client.new(@user, @options.merge(:receipt => true))
              @client.receive_data("CONNECTED\nheart-beat:0,0\nversion:#{version}\n\n\000")
              @client.disconnect.should == "1"
            end

            it "returns receipt-id if enabled locally" do
              @client.disconnect(true).should == "1"
            end
          end

          it "raises ProtocolError if not connected" do
            lambda do
              @client.disconnect
            end.should raise_error(StompOut::ProtocolError, "Not connected")
          end
        end
      end
    end
  end

  context "server commands" do

    CLIENT_SUPPORTED_VERSIONS.each do |version|
      context version do
        context :receive_connected do
          it "notifies user that connected" do
            @client.receive_data("CONNECTED\nserver:RabbitMQ/3.4.1\nsession:1\nversion:#{version}\n\n\000")
            @user.called.should == [:on_connected]
            @user.frame.command.should == "CONNECTED"
            @user.server_name.should == "RabbitMQ/3.4.1"
            @user.session_id.should == "1"
          end

          it "stores information about the session" do
            @client.receive_data("CONNECTED\nserver:RabbitMQ/3.4.1\nsession:1\nversion:#{version}\n\n\000")
            @client.server_name.should == "RabbitMQ/3.4.1"
            @client.session_id.should == "1"
            @client.version.should == version
            @client.connected.should be true
          end

          it "starts heartbeat if specified" do
            timer = flexmock("timer")
            flexmock(EM::PeriodicTimer).should_receive(:new).and_return(timer).twice
            @client.receive_data("CONNECTED\nheart-beat:5000,10000\n\n\000")
            @client.heartbeat.incoming_rate.should == 5000
            @client.heartbeat.outgoing_rate.should == 10000
          end

          it "defaults version to 1.0" do
            @client.receive_data("CONNECTED\n\n\000")
            @client.version.should == "1.0"
          end
        end

        context :receive_message do
          before(:each) do
            @client.receive_data("CONNECTED\nversion:#{version}\n\n\000")
          end

          it "notifies user of the message" do
            @client.subscribe("/queue")
            @client.receive_data("MESSAGE\nack:1\ndestination:/queue\nmessage-id:123\nsubscription:1\n\nhello\000")
            @user.called.should == [:on_connected, :send_data, :on_message]
            @user.frame.command.should == "MESSAGE"
            @user.destination.should == "/queue"
            @user.message.should == "hello"
            @user.message_id.should == "123"
            @user.ack_id.should == "1"
          end

          it "raises ProtocolError if destination header is missing" do
            @client.receive_data("MESSAGE\n\n\000")
            @user.called.should == [:on_connected, :on_error]
            @user.frame.command.should == "ERROR"
            @user.error.should == "Missing 'destination' header"
          end

          it "raises ProtocolError if message-id header is missing" do
            @client.receive_data("MESSAGE\ndestination:/queue\n\n\000")
            @user.called.should == [:on_connected, :on_error]
            @user.frame.command.should == "ERROR"
            @user.error.should == "Missing 'message-id' header"
          end

          if version == "1.0"
            it "does not raise ProtocolError if subscription header is missing" do
              @client.subscribe("/queue")
              @client.receive_data("MESSAGE\ndestination:/queue\nmessage-id:123\n\n\000")
              @user.called.should == [:on_connected, :send_data, :on_message]
            end
          else
            it "raises ProtocolError if subscription header is missing" do
              @client.receive_data("MESSAGE\ndestination:/queue\nmessage-id:123\n\n\000")
              @user.called.should == [:on_connected, :on_error]
              @user.frame.command.should == "ERROR"
              @user.error.should == "Missing 'subscription' header"
            end

            it "raises ApplicationError if subscription does not match destination" do
              @client.subscribe("/queue")
              @client.receive_data("MESSAGE\ndestination:/queue\nmessage-id:123\nsubscription:2\n\n\000")
              @user.called.should == [:on_connected, :send_data, :on_error]
              @user.frame.command.should == "ERROR"
              @user.error.should == "Subscription does not match destination '/queue'"
            end
          end

          it "raise ApplicationError if subscription not found" do
            @client.receive_data("MESSAGE\ndestination:/queue\nmessage-id:123\nsubscription:1\n\n\000")
            @user.called.should == [:on_connected, :on_error]
            @user.frame.command.should == "ERROR"
            @user.error.should == "Subscription to '/queue' not found"
          end

          ["client", "client-individual"].each do |ack|
            context "when ack == #{ack}" do
              before(:each) do
                @client.subscribe("/queue", ack)
              end

              if version == "1.0" && ack != "client-individual"
                it "creates ack ID" do
                  @client.instance_variable_get(:@ack_id).should == 0
                  @client.receive_data("MESSAGE\ndestination:/queue\nmessage-id:123\n\n\000")
                  @client.instance_variable_get(:@ack_id).should == 1
                  @user.ack_id.should == "1"
                end

                it "records message ID associated with given ack ID" do
                  @client.instance_variable_get(:@message_ids)["1"].should be nil
                  @client.receive_data("MESSAGE\ndestination:/queue\nmessage-id:123\n\n\000")
                  @client.instance_variable_get(:@message_ids)["1"].should == "123"
                end

                it "raises ApplicationError if there is more than one message associated with ack ID" do
                  @client.receive_data("MESSAGE\nack:3\ndestination:/queue\nmessage-id:123\n\n\000")
                  @client.receive_data("MESSAGE\nack:3\ndestination:/queue\nmessage-id:456\n\n\000")
                  @user.called.should == [:on_connected, :send_data, :on_message, :on_error]
                  @user.frame.command.should == "ERROR"
                  @user.error.should == "Duplicate ack 3 for messages 123 and 456"
                end
              elsif version == "1.1"
                it "creates ack ID" do
                  @client.instance_variable_get(:@ack_id).should == 0
                  @client.receive_data("MESSAGE\ndestination:/queue\nmessage-id:123\nsubscription:1\n\n\000")
                  @client.instance_variable_get(:@ack_id).should == 1
                  @user.ack_id.should == "1"
                end

                it "records message ID associated with given ack ID" do
                  @client.instance_variable_get(:@message_ids)["1"].should be nil
                  @client.receive_data("MESSAGE\ndestination:/queue\nmessage-id:123\nsubscription:1\n\n\000")
                  @client.instance_variable_get(:@message_ids)["1"].should == "123"
                end
              elsif version > "1.1"
                it "raises ProtocolError if ack header is missing" do
                  @client.receive_data("MESSAGE\ndestination:/queue\nmessage-id:123\nsubscription:1\n\n\000")
                  @user.called.should == [:on_connected, :send_data, :on_error]
                  @user.frame.command.should == "ERROR"
                  @user.error.should == "Missing 'ack' header"
                end

                it "raises ApplicationError if there is more than one message associated with ack ID" do
                  @client.receive_data("MESSAGE\nack:3\ndestination:/queue\nmessage-id:123\nsubscription:1\n\n\000")
                  @client.receive_data("MESSAGE\nack:3\ndestination:/queue\nmessage-id:456\nsubscription:1\n\n\000")
                  @user.called.should == [:on_connected, :send_data, :on_message, :on_error]
                  @user.frame.command.should == "ERROR"
                  @user.error.should == "Duplicate ack 3 for messages 123 and 456"
                end

                it "records message ID associated with given ack ID" do
                  @client.instance_variable_get(:@message_ids)["3"].should be nil
                  @client.receive_data("MESSAGE\nack:3\ndestination:/queue\nmessage-id:123\nsubscription:1\n\n\000")
                  @client.instance_variable_get(:@message_ids)["3"].should == "123"
                end
              end
            end
          end
        end

        context :receive_receipt do
          before(:each) do
            @client.receive_data("CONNECTED\nversion:#{version}\n\n\000")
          end

          it "notifies user of the receipt" do
            @client.message("/queue", "hello", nil, true).should == "1"
            @client.receive_data("RECEIPT\nreceipt-id:1\n\n\000")
            @user.called.should == [:on_connected, :send_data, :on_receipt]
            @user.frame.command.should == "RECEIPT"
            @user.receipt_id.should == "1"
          end

          it "deletes receipted frame" do
            @client.instance_variable_get(:@receipted_frames)["1"].should be nil
            @client.message("/queue", "hello", nil, true).should == "1"
            @client.instance_variable_get(:@receipted_frames)["1"].should be_a(StompOut::Frame)
            @client.receive_data("RECEIPT\nreceipt-id:1\n\n\000")
            @client.instance_variable_get(:@receipted_frames)["1"].should be nil
          end

          it "raises ProtocolError if receipt-id header is missing" do
            @client.receive_data("RECEIPT\n\n\000")
            @user.called.should == [:on_connected, :on_error]
            @user.frame.command.should == "ERROR"
            @user.error.should == "Missing 'receipt-id' header"
          end

          it "raises ApplicationError if request matching receipt not found" do
            @client.receive_data("RECEIPT\nreceipt-id:1\n\n\000")
            @user.called.should == [:on_connected, :on_error]
            @user.frame.command.should == "ERROR"
            @user.error.should == "Request not found matching receipt 1"
          end
        end

        context :receive_error do
          it "notifies user of error" do
            @client.receive_data("ERROR\nmessage:failed\n\nmore info\000")
            @user.called.should == [:on_error]
            @user.frame.command.should == "ERROR"
            @user.error.should == "failed"
            @user.details.should == "more info"
            @user.receipt_id.should be nil
          end

          it "includes receipt-id if there is one" do
            @client.receive_data("ERROR\nmessage:failed\nreceipt-id:3\n\nmore info\000")
            @user.called.should == [:on_error]
            @user.frame.command.should == "ERROR"
            @user.error.should == "failed"
            @user.details.should == "more info"
            @user.receipt_id.should == "3"
          end
        end
      end
    end
  end

  context "support functions" do

    context :process_frame do
      it "sends frame to receive function for processing" do
        frame = StompOut::Frame.new("CONNECTED", {"version" => "1.2"})
        @client.send(:process_frame, frame).should be true
        @user.called.should == [:on_connected]
      end

      it "does not decode body by default" do
        @client.receive_data("CONNECTED\nversion:1.2\n\n\000")
        @client.subscribe("/queue")
        headers = {"ack" => "1", "destination" => "/queue", "message-id" => 123, "subscription" => "1", "content-type" => "application/json"}
        body = JSON.dump({:some => "data"})
        frame = StompOut::Frame.new("MESSAGE", headers, body)
        @client.send(:process_frame, frame).should be true
        @user.called.should == [:on_connected, :send_data, :on_message]
        @user.frame.body.should == body
        @user.message.should == body
      end

      it "decodes body for content-type application/json if :auto_json enabled" do
        @client = StompOut::Client.new(@user, @options.merge(:auto_json => true))
        @client.receive_data("CONNECTED\nversion:1.2\n\n\000")
        @client.subscribe("/queue")
        headers = {"ack" => "1", "destination" => "/queue", "message-id" => 123, "subscription" => "1", "content-type" => "application/json"}
        body = JSON.dump({:some => "data"})
        frame = StompOut::Frame.new("MESSAGE", headers, body)
        @client.send(:process_frame, frame).should be true
        @user.called.should == [:on_connected, :send_data, :on_message]
        @user.frame.body.should == body
        @user.message.should == {"some" => "data"}
      end

      it "raises ProtocolError if it is not a recognized command" do
        lambda do
          @client.send(:process_frame, StompOut::Frame.new("BOGUS"))
        end.should raise_error(StompOut::ProtocolError, "Unhandled frame: BOGUS")
      end
    end

    context :send_frame do
      it "sends frame to server" do
        @client.send(:send_frame, "SEND")
        @user.called.should == [:send_data]
        @user.data.should == "SEND\n\n\000\n"
      end

      it "return frame" do
        frame = @client.send(:send_frame, "SEND")
        frame.command.should == "SEND"
        frame.headers.should == {}
        frame.body.should == ""
      end

      it "adds specified headers to frame" do
        @client.send(:send_frame, "SEND", {"destination" => "/queue"})
        @user.called.should == [:send_data]
        @user.data.should == "SEND\ndestination:/queue\n\n\000\n"
      end

      it "adds receipt header if receipt enabled globally" do
        @client = StompOut::Client.new(@user, @options.merge(:receipt => true))
        @client.send(:send_frame, "SEND", {"destination" => "/queue"})
        @user.called.should == [:send_data]
        @user.data.should == "SEND\ndestination:/queue\nreceipt:1\n\n\000\n"
      end

      it "adds receipt header if receipt enabled locally" do
        @client.send(:send_frame, "SEND", {"destination" => "/queue"}, nil, nil, true)
        @user.called.should == [:send_data]
        @user.data.should == "SEND\ndestination:/queue\nreceipt:1\n\n\000\n"
      end

      it "uses specified content-type but calculates content-length" do
        @client.send(:send_frame, "SEND", {"content-type" => "application/json"}, "{\"some\":\"data\"}")
        @user.called.should == [:send_data]
        @user.data.should == "SEND\ncontent-length:15\ncontent-type:text/plain\n\n{\"some\":\"data\"}\000\n"
      end

      it "sets content-type and content-length headers if there is a body" do
        @client.send(:send_frame, "SEND", nil, "hello")
        @user.called.should == [:send_data]
        @user.data.should == "SEND\ncontent-length:5\ncontent-type:text/plain\n\nhello\000\n"
      end

      it "JSON-encodes body for content-type application/json if :auto_json enabled" do
        @client = StompOut::Client.new(@user, @options.merge(:auto_json => true))
        @client.send(:send_frame, "SEND", nil, {:some => "data"}, "application/json")
        @user.called.should == [:send_data]
        @user.data.should == "SEND\ncontent-length:15\ncontent-type:application/json\n\n{\"some\":\"data\"}\000\n"
      end

      context "when transaction" do
        it "creates transaction header" do
          @client.receive_data("CONNECTED\nversion:1.2\n\n\000")
          transaction_id, _ = @client.begin
          @client.send(:send_frame, "SEND", nil, nil, nil, nil, transaction_id)
          @user.called.should == [:on_connected, :send_data, :send_data]
          @user.data.should == "SEND\ntransaction:1\n\n\000\n"
        end

        it "raises ApplicationError if transaction not found" do
          lambda do
            @client.send(:send_frame, "SEND", nil, nil, nil, nil, "1")
          end.should raise_error(StompOut::ApplicationError, "Transaction not found")
        end
      end
    end
  end
end
