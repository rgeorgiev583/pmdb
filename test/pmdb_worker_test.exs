defmodule PmdbWorkerTest do
  use ExUnit.Case
  doctest Pmdb.Worker

  test "put" do
    assert GenServer.call(Pmdb.Worker, {:put, "foo", 1}) == :ok

    assert :mnesia.transaction(fn -> :mnesia.read(:data, ["foo"]) end) ==
             {:atomic, [{:data, ["foo"], 1}]}
  end

  test "put and get" do
    assert GenServer.call(Pmdb.Worker, {:put, "bar", "baz"}) == :ok

    assert GenServer.call(Pmdb.Worker, {:get, "bar"}) == {:ok, "baz"}
  end
end
