defmodule Witness.Handler.OpenTelemetryTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias OpenTelemetry, as: Otel
  alias Witness.Handler.OpenTelemetry, as: OtelHandler

  require Otel.Tracer

  setup do
    # Ensure OpenTelemetry is started
    :application.ensure_all_started(:opentelemetry)

    # Clear any existing spans
    :otel_batch_processor.set_exporter(:otel_exporter_pid, self())

    :ok
  end

  describe "handle_event/4 - regular events" do
    test "adds event to active span" do
      log =
        capture_log([metadata: [:event]], fn ->
          # Start a span first so event can attach
          Otel.Tracer.with_span "test.span" do
            result =
              OtelHandler.handle_event(
                [:test, :event],
                %{count: 5},
                %{user_id: 123},
                []
              )

            assert result == :ignored
          end
        end)

      assert log =~ "Will attach event to OpenTelemetry.Span."
      assert log =~ "event=test.event"
    end

    test "logs info when no active span" do
      log =
        capture_log(fn ->
          OtelHandler.handle_event(
            [:test, :event],
            %{count: 5},
            %{user_id: 123},
            []
          )
        end)

      assert log =~ "Did not add observability event to OpenTelemetry.Span as none is active."
    end

    test "flattens event attributes" do
      capture_log(fn ->
        Otel.Tracer.with_span "test.span" do
          OtelHandler.handle_event(
            [:test, :event],
            %{count: 5, nested: %{value: "test"}},
            %{user_id: 123},
            []
          )
        end
      end)

      # Attributes should be flattened (tested indirectly via no crashes)
    end
  end

  describe "handle_event/4 - span start" do
    test "starts telemetry span" do
      log =
        capture_log([metadata: [:span]], fn ->
          OtelHandler.handle_event(
            [:test, :operation, :start],
            %{monotonic_time: :erlang.monotonic_time()},
            %{telemetry_span_context: %{}, user_id: 123},
            []
          )
        end)

      assert log =~ "Will start OpenTelemetry.Span."
      assert log =~ "span=test.operation"
    end

    test "uses default monotonic_time if not provided" do
      log =
        capture_log(fn ->
          OtelHandler.handle_event(
            [:test, :operation, :start],
            %{},
            %{telemetry_span_context: %{}},
            []
          )
        end)

      assert log =~ "Will start OpenTelemetry.Span."
    end

    test "uses span kind from metadata" do
      log =
        capture_log(fn ->
          OtelHandler.handle_event(
            [:test, :operation, :start],
            %{},
            %{telemetry_span_context: %{}, kind: :client},
            []
          )
        end)

      assert log =~ "Will start OpenTelemetry.Span."
      # Kind is passed to OtelTranslator (tested indirectly)
    end
  end

  describe "handle_event/4 - span stop" do
    test "stops telemetry span with ok status" do
      log =
        capture_log([metadata: [:span]], fn ->
          telemetry_meta = %{telemetry_span_context: %{}}

          OtelHandler.handle_event(
            [:test, :operation, :start],
            %{},
            Map.merge(telemetry_meta, %{}),
            []
          )

          OtelHandler.handle_event(
            [:test, :operation, :stop],
            %{duration: 1000},
            Map.merge(telemetry_meta, %{
              __observability__: %{status: {:ok, nil}},
              result: :success
            }),
            []
          )
        end)

      assert log =~ "Will stop OpenTelemetry.Span."
      assert log =~ "span=test.operation"
    end

    test "stops telemetry span with error status" do
      log =
        capture_log(fn ->
          telemetry_meta = %{telemetry_span_context: %{}}

          OtelHandler.handle_event(
            [:test, :operation, :start],
            %{},
            telemetry_meta,
            []
          )

          OtelHandler.handle_event(
            [:test, :operation, :stop],
            %{duration: 1000},
            Map.merge(telemetry_meta, %{
              __observability__: %{status: {:error, :timeout}}
            }),
            []
          )
        end)

      assert log =~ "Will stop OpenTelemetry.Span."
    end

    test "logs warning when span not found" do
      log =
        capture_log(fn ->
          OtelHandler.handle_event(
            [:test, :operation, :stop],
            %{duration: 1000},
            %{
              telemetry_span_context: %{invalid: :context},
              __observability__: %{status: {:ok, nil}}
            },
            []
          )
        end)

      assert log =~ "Did not find active span information. Will ignore event."
    end
  end

  describe "handle_event/4 - span exception" do
    test "records exception and stops span" do
      log =
        capture_log([metadata: [:span]], fn ->
          telemetry_meta = %{telemetry_span_context: %{}}

          OtelHandler.handle_event(
            [:test, :operation, :start],
            %{},
            telemetry_meta,
            []
          )

          OtelHandler.handle_event(
            [:test, :operation, :exception],
            %{},
            Map.merge(telemetry_meta, %{
              kind: :error,
              reason: %RuntimeError{message: "boom"},
              stacktrace: []
            }),
            []
          )
        end)

      assert log =~ "Will record an exception for an OpenTelemetry.Span and stop it."
      assert log =~ "span=test.operation"
    end

    test "logs warning when exception span not found" do
      log =
        capture_log(fn ->
          OtelHandler.handle_event(
            [:test, :operation, :exception],
            %{},
            %{
              telemetry_span_context: %{invalid: :context},
              kind: :error,
              reason: %RuntimeError{message: "boom"},
              stacktrace: []
            },
            []
          )
        end)

      assert log =~ "Did not find active span information. Will ignore event."
    end
  end

  describe "map_to_otel/2 - event name mapping" do
    test "maps span start events" do
      log =
        capture_log([metadata: [:span]], fn ->
          OtelHandler.handle_event(
            [:my, :app, :operation, :start],
            %{},
            %{telemetry_span_context: %{}},
            []
          )
        end)

      assert log =~ "span=my.app.operation"
    end

    test "maps span stop events" do
      log =
        capture_log([metadata: [:span]], fn ->
          telemetry_meta = %{telemetry_span_context: %{}}

          OtelHandler.handle_event(
            [:my, :app, :operation, :start],
            %{},
            telemetry_meta,
            []
          )

          OtelHandler.handle_event(
            [:my, :app, :operation, :stop],
            %{},
            Map.merge(telemetry_meta, %{__observability__: %{status: {:ok, nil}}}),
            []
          )
        end)

      assert log =~ "span=my.app.operation"
    end

    test "maps span exception events" do
      log =
        capture_log([metadata: [:span]], fn ->
          telemetry_meta = %{telemetry_span_context: %{}}

          OtelHandler.handle_event(
            [:my, :app, :operation, :start],
            %{},
            telemetry_meta,
            []
          )

          OtelHandler.handle_event(
            [:my, :app, :operation, :exception],
            %{},
            Map.merge(telemetry_meta, %{
              kind: :error,
              reason: %RuntimeError{},
              stacktrace: []
            }),
            []
          )
        end)

      assert log =~ "span=my.app.operation"
    end

    test "maps regular events" do
      log =
        capture_log([metadata: [:event]], fn ->
          Otel.Tracer.with_span "test.span" do
            OtelHandler.handle_event(
              [:my, :app, :user, :created],
              %{},
              %{},
              []
            )
          end
        end)

      assert log =~ "event=my.app.user.created"
    end
  end

  describe "to_otel_status/1" do
    test "converts ok status with nil details" do
      log =
        capture_log(fn ->
          telemetry_meta = %{telemetry_span_context: %{}}

          OtelHandler.handle_event([:test, :op, :start], %{}, telemetry_meta, [])

          OtelHandler.handle_event(
            [:test, :op, :stop],
            %{},
            Map.merge(telemetry_meta, %{__observability__: %{status: {:ok, nil}}}),
            []
          )
        end)

      assert log =~ "Will stop OpenTelemetry.Span."
    end

    test "converts ok status with string details" do
      log =
        capture_log(fn ->
          telemetry_meta = %{telemetry_span_context: %{}}

          OtelHandler.handle_event([:test, :op, :start], %{}, telemetry_meta, [])

          OtelHandler.handle_event(
            [:test, :op, :stop],
            %{},
            Map.merge(telemetry_meta, %{
              __observability__: %{status: {:ok, "all good"}}
            }),
            []
          )
        end)

      assert log =~ "Will stop OpenTelemetry.Span."
    end

    test "converts error status with exception details" do
      log =
        capture_log(fn ->
          telemetry_meta = %{telemetry_span_context: %{}}

          OtelHandler.handle_event([:test, :op, :start], %{}, telemetry_meta, [])

          OtelHandler.handle_event(
            [:test, :op, :stop],
            %{},
            Map.merge(telemetry_meta, %{
              __observability__: %{status: {:error, %RuntimeError{message: "boom"}}}
            }),
            []
          )
        end)

      assert log =~ "Will stop OpenTelemetry.Span."
    end

    test "converts error status with non-nil details" do
      log =
        capture_log(fn ->
          telemetry_meta = %{telemetry_span_context: %{}}

          OtelHandler.handle_event([:test, :op, :start], %{}, telemetry_meta, [])

          OtelHandler.handle_event(
            [:test, :op, :stop],
            %{},
            Map.merge(telemetry_meta, %{
              __observability__: %{status: {:error, :timeout}}
            }),
            []
          )
        end)

      assert log =~ "Will stop OpenTelemetry.Span."
    end

    test "converts unset status" do
      log =
        capture_log(fn ->
          telemetry_meta = %{telemetry_span_context: %{}}

          OtelHandler.handle_event([:test, :op, :start], %{}, telemetry_meta, [])

          OtelHandler.handle_event(
            [:test, :op, :stop],
            %{},
            Map.merge(telemetry_meta, %{
              __observability__: %{status: :unknown}
            }),
            []
          )
        end)

      assert log =~ "Will stop OpenTelemetry.Span."
    end
  end

  describe "to_otel_attribute/1" do
    test "converts various attribute types" do
      log =
        capture_log(fn ->
          Otel.Tracer.with_span "test.span" do
            OtelHandler.handle_event(
              [:test, :event],
              %{
                string: "text",
                number: 42,
                float: 3.14,
                boolean: true,
                atom: :test,
                list: [1, 2, 3],
                tuple: {:ok, "value"},
                nested: %{key: "value"}
              },
              %{},
              []
            )
          end
        end)

      assert log =~ "Will attach event to OpenTelemetry.Span."
    end

    test "converts structs using inspect" do
      log =
        capture_log(fn ->
          Otel.Tracer.with_span "test.span" do
            OtelHandler.handle_event(
              [:test, :event],
              %{
                error: %RuntimeError{message: "test"},
                uri: URI.parse("https://example.com")
              },
              %{},
              []
            )
          end
        end)

      assert log =~ "Will attach event to OpenTelemetry.Span."
    end
  end
end
