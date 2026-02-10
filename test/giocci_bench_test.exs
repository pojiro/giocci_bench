defmodule GiocciBenchTest do
  use ExUnit.Case
  doctest GiocciBench

  test "greets the world" do
    assert GiocciBench.hello() == :world
  end
end
