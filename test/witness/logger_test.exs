defmodule Witness.LoggerTest do
  use ExUnit.Case, async: true

  require Witness.Logger, as: WLog

  defmodule TestContext do
    use Witness,
      app: :witness,
      prefix: [:test]
  end

  setup do
    # Attach telemetry test handler
    test_pid = self()
    handler_id = make_ref()

    :telemetry.attach_many(
      handler_id,
      [
        [:test, :log, :debug],
        [:test, :log, :info],
        [:test, :log, :notice],
        [:test, :log, :warning],
        [:test, :log, :error],
        [:test, :log, :critical],
        [:test, :log, :alert],
        [:test, :log, :emergency]
      ],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    :ok
  end

  describe "debug/3" do
    test "emits [:log, :debug] event with message" do
      WLog.debug(TestContext, "Debug message")

      assert_receive {:telemetry_event, [:test, :log, :debug], measurements, _metadata}
      assert measurements.message == "Debug message"
    end

    test "emits [:log, :debug] event with metadata" do
      WLog.debug(TestContext, "Debug message", user_id: 123)

      assert_receive {:telemetry_event, [:test, :log, :debug], measurements, _metadata}
      assert measurements.message == "Debug message"
      assert measurements.user_id == 123
    end

    test "accepts iodata as message" do
      WLog.debug(TestContext, ["User ", "123", " logged in"])

      assert_receive {:telemetry_event, [:test, :log, :debug], measurements, _metadata}
      assert measurements.message == ["User ", "123", " logged in"]
    end
  end

  describe "info/3" do
    test "emits [:log, :info] event" do
      WLog.info(TestContext, "Info message")

      assert_receive {:telemetry_event, [:test, :log, :info], measurements, _metadata}
      assert measurements.message == "Info message"
    end
  end

  describe "notice/3" do
    test "emits [:log, :notice] event" do
      WLog.notice(TestContext, "Notice message")

      assert_receive {:telemetry_event, [:test, :log, :notice], measurements, _metadata}
      assert measurements.message == "Notice message"
    end
  end

  describe "warning/3" do
    test "emits [:log, :warning] event" do
      WLog.warning(TestContext, "Warning message")

      assert_receive {:telemetry_event, [:test, :log, :warning], measurements, _metadata}
      assert measurements.message == "Warning message"
    end
  end

  describe "error/3" do
    test "emits [:log, :error] event" do
      WLog.error(TestContext, "Error message")

      assert_receive {:telemetry_event, [:test, :log, :error], measurements, _metadata}
      assert measurements.message == "Error message"
    end
  end

  describe "critical/3" do
    test "emits [:log, :critical] event" do
      WLog.critical(TestContext, "Critical message")

      assert_receive {:telemetry_event, [:test, :log, :critical], measurements, _metadata}
      assert measurements.message == "Critical message"
    end
  end

  describe "alert/3" do
    test "emits [:log, :alert] event" do
      WLog.alert(TestContext, "Alert message")

      assert_receive {:telemetry_event, [:test, :log, :alert], measurements, _metadata}
      assert measurements.message == "Alert message"
    end
  end

  describe "emergency/3" do
    test "emits [:log, :emergency] event" do
      WLog.emergency(TestContext, "Emergency message")

      assert_receive {:telemetry_event, [:test, :log, :emergency], measurements, _metadata}
      assert measurements.message == "Emergency message"
    end
  end

  describe "log/4" do
    test "emits event at specified level" do
      WLog.log(TestContext, :info, "Dynamic level message")

      assert_receive {:telemetry_event, [:test, :log, :info], measurements, _metadata}
      assert measurements.message == "Dynamic level message"
    end

    test "accepts metadata" do
      WLog.log(TestContext, :debug, "Message", key: "value")

      assert_receive {:telemetry_event, [:test, :log, :debug], measurements, _metadata}
      assert measurements.message == "Message"
      assert measurements.key == "value"
    end
  end
end
