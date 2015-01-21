require 'spec_helper'
require 'eventmachine'

describe StompOut::Heartbeat do

  before(:each) do
    @service = flexmock("stomp client or server")
  end

  context :usable? do
    it "returns true if eventmachine can be loaded" do
      flexmock(StompOut::Heartbeat).should_receive(:require).with("eventmachine").and_return(true).once
      StompOut::Heartbeat.usable?.should be true
    end

    it "returns false if eventmachine cannot be loaded" do
      flexmock(StompOut::Heartbeat).should_receive(:require).with("eventmachine").and_raise(LoadError).once
      StompOut::Heartbeat.usable?.should be false
    end
  end

  context :initialize do
    it "calculates incoming and outgoing rate" do
      heartbeat = StompOut::Heartbeat.new(@service, "5000,10000", 15000, 5000)
      heartbeat.incoming_rate.should == 15000
      heartbeat.outgoing_rate.should == 10000
    end

    it "raises ProtocolError if the specified heartbeat is not a comma-separated list" do
      lambda do
        StompOut::Heartbeat.new(@service, "5000")
      end.should raise_error(StompOut::ProtocolError, "Invalid 'heart-beat' header")
    end

    it "raises ProtocolError if the specified heartbeat is not a comma-separated of integers" do
      lambda do
        StompOut::Heartbeat.new(@service, "5000,none")
      end.should raise_error(StompOut::ProtocolError, "Invalid 'heart-beat' header")
    end
  end

  context :start do
    it "starts monitoring for heartbeats if incoming heartbeats are configured" do
      flexmock(EM::PeriodicTimer).should_receive(:new).once
      heartbeat = StompOut::Heartbeat.new(@service, "5000,0", 15000, 0)
      heartbeat.start
    end

    it "starts generating heartbeats if outgoing heartbeats are configured" do
      flexmock(EM::PeriodicTimer).should_receive(:new).once
      heartbeat = StompOut::Heartbeat.new(@service, "0,10000", 0, 5000)
      heartbeat.start
    end

    it "starts nothing if there is no heartbeat configured" do
      flexmock(EM::PeriodicTimer).should_receive(:new).never
      heartbeat = StompOut::Heartbeat.new(@service, "0,0", 0, 0)
      heartbeat.start
    end
  end

  context :stop do
    it "stops incoming and outgoing heartbeat activity" do
      timer = flexmock("timer")
      timer.should_receive(:cancel).twice
      flexmock(EM::PeriodicTimer).should_receive(:new).and_return(timer).twice
      heartbeat = StompOut::Heartbeat.new(@service, "5000,10000", 15000, 5000)
      heartbeat.start
      heartbeat.instance_variable_get(:@incoming_timer).should == timer
      heartbeat.instance_variable_get(:@outgoing_timer).should == timer
      heartbeat.stop
      heartbeat.instance_variable_get(:@incoming_timer).should be nil
      heartbeat.instance_variable_get(:@outgoing_timer).should be nil
    end
  end

  context :sent_data do
    it "updates that data has been sent" do
      heartbeat = StompOut::Heartbeat.new(@service, nil)
      heartbeat.sent_data
      heartbeat.instance_variable_get(:@sent_data).should be true
    end
  end

  context :received_data do
    it "updates that data has been received" do
      heartbeat = StompOut::Heartbeat.new(@service, nil)
      heartbeat.received_data
      heartbeat.instance_variable_get(:@received_data).should be true
    end
  end

  context :monitor_incoming do
    before(:each) do
      @heartbeat = StompOut::Heartbeat.new(@service, "5000,0", 15000, 0)
      flexmock(EM::PeriodicTimer).should_receive(:new).by_default
    end

    it "periodically checks that data has been received within a tolerance margin" do
      flexmock(EM::PeriodicTimer).should_receive(:new).with(22.5, Proc).once
      heartbeat = StompOut::Heartbeat.new(@service, "5000,0", 15000, 0)
      heartbeat.start
    end

    it "notifies service and stops heartbeat if a heartbeat is missed" do
      flexmock(EM::PeriodicTimer).should_receive(:new).and_yield.once
      heartbeat = StompOut::Heartbeat.new(@service, "5000,0", 15000, 0)
      @service.should_receive(:report_error).with("heartbeat failure").once
      flexmock(heartbeat).should_receive(:stop).once
      heartbeat.start
    end

    it "does nothing if data has been received within interval" do
      flexmock(EM::PeriodicTimer).should_receive(:new).and_yield.once
      heartbeat = StompOut::Heartbeat.new(@service, "5000,0", 15000, 0)
      heartbeat.received_data
      heartbeat.start
    end
  end

  context :generate_outgoing do
    before(:each) do
      @heartbeat = StompOut::Heartbeat.new(@service, "0,10000", 0, 5000)
      flexmock(EM::PeriodicTimer).should_receive(:new).by_default
    end

    it "periodically checks that data has been sent" do
      flexmock(EM::PeriodicTimer).should_receive(:new).with(10.0, Proc).once
      heartbeat = StompOut::Heartbeat.new(@service, "0,10000", 0, 5000)
      heartbeat.start
    end

    it "sends heartbeat if no data has been sent for given interval" do
      flexmock(EM::PeriodicTimer).should_receive(:new).and_yield.once
      heartbeat = StompOut::Heartbeat.new(@service, "0,10000", 0, 5000)
      @service.should_receive(:send_data).with("\n").once
      heartbeat.start
    end

    it "send heartbeat if no data has been sent for given interval" do
      flexmock(EM::PeriodicTimer).should_receive(:new).and_yield.once
      heartbeat = StompOut::Heartbeat.new(@service, "0,10000", 0, 5000)
      heartbeat.sent_data
      heartbeat.start
    end
  end
end
