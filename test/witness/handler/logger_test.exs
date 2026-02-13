defmodule Witness.Handler.LoggerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Witness.Handler.Logger, as: LoggerHandler

  describe "handle_event/4 - log level determination" do
    test "uses explicit log_level from metadata" do
      log =
        capture_log(fn ->
          LoggerHandler.handle_event(
            [:test, :event],
            %{},
            %{log_level: :warning, foo: "bar"},
            []
          )
        end)

      assert log =~ "[warning]"
      assert log =~ "[Event] test.event"
    end

    test "extracts level from Witness.Logger event [:log, level]" do
      log =
        capture_log(fn ->
          LoggerHandler.handle_event(
            [:app, :log, :info],
            %{},
            %{message: "test"},
            []
          )
        end)

      assert log =~ "[info]"
    end

    test "extracts level from Witness.Logger span event [:log, level, :start]" do
      log =
        capture_log(fn ->
          LoggerHandler.handle_event(
            [:app, :log, :error, :start],
            %{},
            %{message: "test"},
            []
          )
        end)

      assert log =~ "[error]"
    end

    test "logs exception events at error level" do
      log =
        capture_log(fn ->
          LoggerHandler.handle_event(
            [:test, :span, :exception],
            %{},
            %{kind: :error, reason: %RuntimeError{message: "boom"}},
            []
          )
        end)

      assert log =~ "[error]"
      assert log =~ "[Span Exception]"
    end

    test "logs error status spans at warning level" do
      log =
        capture_log(fn ->
          LoggerHandler.handle_event(
            [:test, :span, :stop],
            %{duration: 1000},
            %{__observability__: %{status: {:error, :timeout}, context: :test}},
            []
          )
        end)

      assert log =~ "[warning]"
      assert log =~ "(error: :timeout)"
    end

    test "uses default debug level when no special conditions" do
      log =
        capture_log(fn ->
          LoggerHandler.handle_event(
            [:test, :event],
            %{},
            %{},
            []
          )
        end)

      assert log =~ "[debug]"
    end

    test "uses configured default level" do
      log =
        capture_log(fn ->
          LoggerHandler.handle_event(
            [:test, :event],
            %{},
            %{},
            level: :info
          )
        end)

      assert log =~ "[info]"
    end
  end

  describe "handle_event/4 - message formatting" do
    test "formats span start events" do
      log =
        capture_log(fn ->
          LoggerHandler.handle_event(
            [:test, :operation, :start],
            %{count: 5},
            %{user_id: 123},
            []
          )
        end)

      assert log =~ "[Span Start] test.operation.start"
      assert log =~ "count=5"
      assert log =~ "user_id=123"
    end

    test "formats span stop events with ok status" do
      log =
        capture_log(fn ->
          LoggerHandler.handle_event(
            [:test, :operation, :stop],
            %{duration: 1_500_000},
            %{__observability__: %{status: {:ok, nil}, context: :test}},
            []
          )
        end)

      assert log =~ "[Span Stop] test.operation.stop"
      assert log =~ "(ok)"
      assert log =~ "duration="
    end

    test "formats span stop events with ok status and details" do
      log =
        capture_log(fn ->
          LoggerHandler.handle_event(
            [:test, :operation, :stop],
            %{duration: 1000},
            %{__observability__: %{status: {:ok, :completed}, context: :test}},
            []
          )
        end)

      assert log =~ "(ok: :completed)"
    end

    test "formats span stop events with error status and details" do
      log =
        capture_log(fn ->
          LoggerHandler.handle_event(
            [:test, :operation, :stop],
            %{duration: 1000},
            %{__observability__: %{status: {:error, :failed}, context: :test}},
            []
          )
        end)

      assert log =~ "(error: :failed)"
    end

    test "formats span exception events" do
      log =
        capture_log(fn ->
          LoggerHandler.handle_event(
            [:test, :operation, :exception],
            %{},
            %{kind: :error, reason: %RuntimeError{message: "boom"}},
            []
          )
        end)

      assert log =~ "[Span Exception] test.operation.exception"
      assert log =~ ":error"
      assert log =~ "RuntimeError"
    end

    test "formats regular events" do
      log =
        capture_log(fn ->
          LoggerHandler.handle_event(
            [:test, :user, :created],
            %{user_id: 456},
            %{email: "test@example.com"},
            []
          )
        end)

      assert log =~ "[Event] test.user.created"
      assert log =~ "user_id=456"
      assert log =~ ~s(email="test@example.com")
    end

    test "formats events with empty measurements and metadata" do
      log =
        capture_log(fn ->
          LoggerHandler.handle_event(
            [:test, :simple],
            %{},
            %{},
            []
          )
        end)

      assert log =~ "[Event] test.simple"
      refute log =~ " | "
    end
  end

  describe "handle_event/4 - duration formatting" do
    test "formats microseconds" do
      log =
        capture_log(fn ->
          LoggerHandler.handle_event(
            [:test, :op, :stop],
            %{duration: System.convert_time_unit(500, :microsecond, :native)},
            %{observability: %{status: {:ok, nil}, context: :test}},
            []
          )
        end)

      assert log =~ "500µs"
    end

    test "formats milliseconds" do
      log =
        capture_log(fn ->
          LoggerHandler.handle_event(
            [:test, :op, :stop],
            %{duration: System.convert_time_unit(2_500, :microsecond, :native)},
            %{observability: %{status: {:ok, nil}, context: :test}},
            []
          )
        end)

      assert log =~ "2.5ms"
    end

    test "formats seconds" do
      log =
        capture_log(fn ->
          LoggerHandler.handle_event(
            [:test, :op, :stop],
            %{duration: System.convert_time_unit(3_500_000, :microsecond, :native)},
            %{observability: %{status: {:ok, nil}, context: :test}},
            []
          )
        end)

      assert log =~ "3.5s"
    end

    test "handles span stop without duration" do
      log =
        capture_log(fn ->
          LoggerHandler.handle_event(
            [:test, :op, :stop],
            %{},
            %{__observability__: %{status: {:ok, nil}, context: :test}},
            []
          )
        end)

      assert log =~ "[Span Stop]"
      refute log =~ "duration="
    end
  end

  describe "handle_event/4 - metadata handling" do
    test "strips internal observability metadata" do
      log =
        capture_log(fn ->
          LoggerHandler.handle_event(
            [:test, :event],
            %{},
            %{
              __observability__: %{context: :test, status: {:ok, nil}},
              user_data: "visible"
            },
            []
          )
        end)

      assert log =~ "user_data"
      refute log =~ "__observability__"
    end

    test "strips telemetry internal metadata" do
      log =
        capture_log(fn ->
          LoggerHandler.handle_event(
            [:test, :event],
            %{},
            %{
              telemetry_span_context: :internal,
              caller: {__MODULE__, :test, 1},
              user_data: "visible"
            },
            []
          )
        end)

      assert log =~ "user_data"
      refute log =~ "telemetry_span_context"
      refute log =~ "caller"
    end

    test "includes context in logger metadata" do
      log =
        capture_log([metadata: [:context]], fn ->
          LoggerHandler.handle_event(
            [:test, :event],
            %{},
            %{__observability__: %{context: :my_context}},
            []
          )
        end)

      assert log =~ "context=my_context"
    end
  end

  describe "handle_event/4 - exception formatting" do
    test "formats exception with kind and reason" do
      log =
        capture_log(fn ->
          LoggerHandler.handle_event(
            [:test, :op, :exception],
            %{},
            %{
              kind: :error,
              reason: %RuntimeError{message: "something broke"}
            },
            []
          )
        end)

      assert log =~ ":error"
      assert log =~ "RuntimeError"
      assert log =~ "something broke"
    end

    test "handles exception events without proper exception metadata" do
      log =
        capture_log(fn ->
          LoggerHandler.handle_event(
            [:test, :op, :exception],
            %{},
            %{some: :data},
            []
          )
        end)

      assert log =~ "[Span Exception]"
      # Should not crash, just format without exception details
    end
  end

  describe "handle_event/4 - span status edge cases" do
    test "formats span stop with non-standard status" do
      log =
        capture_log(fn ->
          LoggerHandler.handle_event(
            [:test, :op, :stop],
            %{duration: 1000},
            %{__observability__: %{status: :unknown, context: :test}},
            []
          )
        end)

      assert log =~ "[Span Stop]"
      # Should handle gracefully without status formatting
    end
  end
end
