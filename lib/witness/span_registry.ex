defmodule Witness.SpanRegistry do
  @moduledoc """
  ETS-based registry for tracking active spans across process boundaries.

  Stores `{pid, context, span_ref}` tuples to maintain span hierarchy
  when crossing process boundaries.
  """

  use GenServer

  @type context :: Witness.t()
  @type span_ref :: reference()

  @doc """
  Starts the span registry.
  """
  def start_link(context) do
    GenServer.start_link(__MODULE__, context, name: registry_name(context))
  end

  @doc """
  Child spec for supervision tree.
  """
  def child_spec(context) do
    %{
      id: {__MODULE__, context},
      start: {__MODULE__, :start_link, [context]},
      type: :worker
    }
  end

  @doc """
  Registers the current span for the calling process.
  """
  @spec register_span(context, span_ref) :: :ok
  def register_span(context, span_ref) do
    table = table_name(context)
    :ets.insert(table, {self(), span_ref})
    :ok
  end

  @doc """
  Unregisters the span for the calling process.
  """
  @spec unregister_span(context) :: :ok
  def unregister_span(context) do
    table = table_name(context)
    :ets.delete(table, self())
    :ok
  end

  @doc """
  Looks up the active span for the given PID.
  """
  @spec lookup_span(context, pid) :: {:ok, span_ref} | :error
  def lookup_span(context, pid) do
    table = table_name(context)

    case :ets.lookup(table, pid) do
      [{^pid, span_ref}] -> {:ok, span_ref}
      [] -> :error
    end
  end

  @doc """
  Looks up the parent span by checking the calling process's parent.

  This enables cross-process span propagation.
  """
  @spec lookup_parent_span(context) :: {:ok, span_ref} | :error
  def lookup_parent_span(context) do
    # Get the parent process from the process dictionary
    # This works for Task and other standard OTP patterns
    case Process.get(:"$ancestors") do
      [parent_pid | _] when is_pid(parent_pid) ->
        lookup_span(context, parent_pid)

      _ ->
        :error
    end
  end

  ## GenServer Callbacks

  @impl true
  def init(context) do
    table =
      :ets.new(table_name(context), [
        :set,
        :public,
        :named_table,
        {:read_concurrency, true},
        {:write_concurrency, true}
      ])

    {:ok, %{context: context, table: table}}
  end

  ## Private

  defp registry_name(context), do: Module.concat(context, SpanRegistry)
  defp table_name(context), do: Module.concat(context, SpanRegistryTable)
end
