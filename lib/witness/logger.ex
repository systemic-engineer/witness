defmodule Witness.Logger do
  @moduledoc """
  A Logger-like interface that emits telemetry events through Witness.

  ## Usage

      require MyObservabilityContext, as: O11y
      require Witness.Logger, as: WLog

      WLog.info(O11y, "User created", user_id: 123)
      WLog.debug(O11y, "Processing request", path: "/api/users")
      WLog.error(O11y, "Database connection failed", reason: :timeout)

  ## Events

  Each function emits a single telemetry event:
  - `debug/3` → `[:log, :debug]`
  - `info/3` → `[:log, :info]`
  - `notice/3` → `[:log, :notice]`
  - `warning/3` → `[:log, :warning]`
  - `error/3` → `[:log, :error]`
  - `critical/3` → `[:log, :critical]`
  - `alert/3` → `[:log, :alert]`
  - `emergency/3` → `[:log, :emergency]`

  These events are picked up by `Witness.Handler.Logger` which logs them
  using Elixir's `Logger` at the appropriate level.

  ## Message Format

  Messages can be strings or iodata:

      WLog.info(O11y, "Simple message")
      WLog.info(O11y, ["User ", user_id, " logged in"])

  ## Metadata

  Additional metadata can be provided as the third argument:

      WLog.info(O11y, "Request completed", duration: 150, status: 200)

  The metadata is merged with the message as event attributes.
  """

  require Witness.Tracker, as: Tracker

  @type context :: Witness.t()
  @type message :: String.t() | iodata
  @type metadata :: keyword | map

  @empty_map Macro.escape(%{})

  for level <- Logger.levels() do
    @doc """
    Logs a #{level} message.

    Emits a `[:log, :#{level}]` event.
    """
    defmacro unquote(level)(context, message, metadata \\ @empty_map) do
      level = unquote(level)

      quote do
        unquote(__MODULE__).log(
          unquote(context),
          unquote(level),
          unquote(message),
          unquote(metadata)
        )
      end
    end
  end

  @doc """
  Logs a message at the given level.

  This is the underlying implementation for all level-specific macros.

  ## Examples

      require MyObservabilityContext, as: O11y
      require Witness.Logger, as: WLog

      level = :info
      WLog.log(O11y, level, "Dynamic level logging")
  """
  defmacro log(context, level, message, metadata \\ @empty_map) do
    quote do
      Tracker._track_event(
        unquote(context),
        [:log, unquote(level)],
        Map.put(Witness.Utils.as_map(unquote(metadata)), :message, unquote(message)),
        %{}
      )
    end
  end
end
