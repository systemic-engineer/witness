defmodule Witness.SupervisorTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  defmodule ActiveContext do
    use Witness,
      app: :witness,
      prefix: [:test, :supervisor],
      active: true
  end

  defmodule InactiveContext do
    use Witness,
      app: :witness,
      prefix: [:test, :inactive],
      active: false
  end

  defmodule ContextWithHandlers do
    use Witness,
      app: :witness,
      prefix: [:test, :with_handlers],
      handler: [
        Witness.Handler.Logger,
        {Witness.Handler.OpenTelemetry, custom: :config}
      ]
  end

  describe "child_spec/1" do
    test "returns valid child_spec for a context" do
      spec = Witness.Supervisor.child_spec(ActiveContext)

      assert spec.id == {Witness.Supervisor, ActiveContext}
      assert spec.start == {Witness.Supervisor, :start_link, [ActiveContext]}
      assert spec.type == :supervisor
    end
  end

  describe "start_link/1" do
    test "starts supervisor for active context" do
      log =
        capture_log(fn ->
          {:ok, pid} = Witness.Supervisor.start_link(ActiveContext)
          assert is_pid(pid)
          assert Process.alive?(pid)

          # Cleanup
          Supervisor.stop(pid)
        end)

      assert log =~ "Will load and start all handlers for context."
    end

    test "starts supervisor for inactive context" do
      log =
        capture_log(fn ->
          {:ok, pid} = Witness.Supervisor.start_link(InactiveContext)
          assert is_pid(pid)
          assert Process.alive?(pid)

          # Cleanup
          Supervisor.stop(pid)
        end)

      assert log =~ "Will not attach or start handlers for context, as it's inactive."
    end
  end

  describe "init/1 with active context" do
    test "initializes with SpanRegistry and handlers" do
      log =
        capture_log(fn ->
          pid = start_supervised!(ActiveContext)
          assert is_pid(pid)
          assert Process.alive?(pid)
        end)

      assert log =~ "Will load and start all handlers for context."
    end

    test "loads handlers with and without config" do
      log =
        capture_log(fn ->
          pid = start_supervised!(ContextWithHandlers)
          assert is_pid(pid)
          assert Process.alive?(pid)
        end)

      assert log =~ "Will load and start all handlers for context."
      # Both handlers should be attached
      assert log =~ "Will attach handler to all events in context."
    end
  end

  describe "init/1 with inactive context" do
    test "initializes with empty children list" do
      log =
        capture_log(fn ->
          pid = start_supervised!(InactiveContext)
          assert is_pid(pid)
          assert Process.alive?(pid)

          # Verify no children were started
          children = Supervisor.which_children(InactiveContext)
          # SpanRegistry should not be started for inactive context
          refute Enum.any?(children, fn {id, _pid, _type, _modules} ->
                   match?({Witness.SpanRegistry, _}, id)
                 end)
        end)

      assert log =~ "Will not attach or start handlers for context, as it's inactive."
    end
  end
end
