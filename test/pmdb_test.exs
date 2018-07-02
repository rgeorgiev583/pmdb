defmodule PmdbTest do
  use ExUnit.Case
  doctest Pmdb

  test "greets the world" do
    assert Pmdb.hello() == :world
  end
end
