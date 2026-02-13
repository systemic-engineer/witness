defmodule Witness.SpanTest do
  use ExUnit.Case, async: true

  alias Witness.Span

  import Witness.Span

  doctest Span

  defmodule TestContext do
    use Witness,
      app: :witness,
      prefix: [:test]
  end

  describe "new/3" do
    test "creates span with defaults" do
      span = Span.new(TestContext, [:test, :event])

      assert is_reference(span.id)
      assert span.context == TestContext
      assert span.event_name == [:test, :event]
      assert span.meta == %{}
      assert span.status == :unknown
      assert is_nil(span.result)
    end

    test "creates span with custom attributes" do
      custom_id = make_ref()
      span = Span.new(TestContext, [:test, :event], id: custom_id, meta: %{foo: "bar"})

      assert span.id == custom_id
      assert span.meta == %{foo: "bar"}
    end
  end

  describe "with_meta/2" do
    test "merges metadata" do
      span = Span.new(TestContext, [:test])
      updated = Span.with_meta(span, %{foo: "bar"})

      assert updated.meta == %{foo: "bar"}
    end

    test "merges with existing metadata" do
      span = Span.new(TestContext, [:test], meta: %{existing: "value"})
      updated = Span.with_meta(span, %{new: "value"})

      assert updated.meta == %{existing: "value", new: "value"}
    end

    test "overwrites existing keys" do
      span = Span.new(TestContext, [:test], meta: %{key: "old"})
      updated = Span.with_meta(span, %{key: "new"})

      assert updated.meta == %{key: "new"}
    end

    test "handles nil meta" do
      span = %Span{id: make_ref(), context: TestContext, event_name: [:test], meta: nil}
      updated = Span.with_meta(span, %{foo: "bar"})

      assert updated.meta == %{foo: "bar"}
    end
  end

  describe "with_result/2 with unknown status" do
    test "sets result and infers status from :ok" do
      span = Span.new(TestContext, [:test])
      updated = Span.with_result(span, :ok)

      assert updated.result == :ok
      assert updated.status == {:ok, nil}
    end

    test "sets result and infers status from {:ok, value}" do
      span = Span.new(TestContext, [:test])
      updated = Span.with_result(span, {:ok, "value"})

      assert updated.result == {:ok, "value"}
      assert updated.status == {:ok, nil}
    end

    test "sets result and infers status from :error" do
      span = Span.new(TestContext, [:test])
      updated = Span.with_result(span, :error)

      assert updated.result == :error
      assert updated.status == {:error, nil}
    end

    test "sets result and infers status from {:error, reason}" do
      span = Span.new(TestContext, [:test])
      updated = Span.with_result(span, {:error, :timeout})

      assert updated.result == {:error, :timeout}
      assert updated.status == {:error, :timeout}
    end

    test "sets result with unknown status for other values" do
      span = Span.new(TestContext, [:test])
      updated = Span.with_result(span, "some value")

      assert updated.result == "some value"
      assert updated.status == :unknown
    end
  end

  describe "with_result/2 with existing status" do
    test "preserves existing status" do
      span = Span.new(TestContext, [:test], status: {:ok, "existing"})
      updated = Span.with_result(span, :different_result)

      assert updated.result == :different_result
      assert updated.status == {:ok, "existing"}
    end
  end

  describe "with_status/3" do
    test "sets :ok status" do
      span = Span.new(TestContext, [:test])
      updated = Span.with_status(span, :ok)

      assert updated.status == {:ok, nil}
    end

    test "sets :ok status with details" do
      span = Span.new(TestContext, [:test])
      updated = Span.with_status(span, :ok, "completed")

      assert updated.status == {:ok, "completed"}
    end

    test "sets :error status" do
      span = Span.new(TestContext, [:test])
      updated = Span.with_status(span, :error)

      assert updated.status == {:error, nil}
    end

    test "sets :error status with details" do
      span = Span.new(TestContext, [:test])
      updated = Span.with_status(span, :error, :timeout)

      assert updated.status == {:error, :timeout}
    end

    test "sets :unknown status" do
      span = Span.new(TestContext, [:test], status: {:ok, nil})
      updated = Span.with_status(span, :unknown)

      assert updated.status == :unknown
    end

    test "ignores details for :unknown status" do
      span = Span.new(TestContext, [:test])
      updated = Span.with_status(span, :unknown, "ignored")

      assert updated.status == :unknown
    end
  end

  describe "status_of/1" do
    test "returns {:ok, nil} for :ok" do
      assert status_of(:ok) == {:ok, nil}
    end

    test "returns {:ok, nil} for {:ok, value}" do
      assert status_of({:ok, "value"}) == {:ok, nil}
    end

    test "returns {:ok, nil} for {:ok, value1, value2}" do
      assert status_of({:ok, "v1", "v2"}) == {:ok, nil}
    end

    test "returns {:error, nil} for :error" do
      assert status_of(:error) == {:error, nil}
    end

    test "returns {:error, reason} for {:error, reason}" do
      assert status_of({:error, :timeout}) == {:error, :timeout}
    end

    test "returns {:error, {reason, details}} for {:error, reason, details}" do
      assert status_of({:error, :network, :timeout}) == {:error, {:network, :timeout}}
    end

    test "returns :unknown for other values" do
      assert status_of("string") == :unknown
      assert status_of(123) == :unknown
      assert status_of(nil) == :unknown
    end
  end
end
