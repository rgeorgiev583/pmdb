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

  test "put and get list" do
    assert GenServer.call(Pmdb.Worker, {:put, "quux", ["a"]}) == :ok
    assert GenServer.call(Pmdb.Worker, {:get, "quux.[0]"}) == {:ok, "a"}
  end

  test "nested put and get" do
    assert GenServer.call(Pmdb.Worker, {:put, "bar.baz", false}) == :ok
    assert GenServer.call(Pmdb.Worker, {:get, "bar.baz"}) == {:ok, false}
  end

  test "put and get map" do
    assert GenServer.call(Pmdb.Worker, {:put, "lol", %{"a" => "b", "c" => "d"}}) == :ok
    assert GenServer.call(Pmdb.Worker, {:get, "lol.c"}) == {:ok, "d"}
  end

  test "put and delete" do
    assert GenServer.call(Pmdb.Worker, {:put, "lel.lul", -1}) == :ok
    assert GenServer.call(Pmdb.Worker, {:get, "lel.lul"}) == {:ok, -1}
    assert GenServer.call(Pmdb.Worker, {:delete, "lel"}) == :ok
    assert GenServer.call(Pmdb.Worker, {:get, "lel.lul"}) != {:ok, -1}
  end
end
