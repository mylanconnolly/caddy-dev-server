defmodule CaddyDevServerTest do
  use ExUnit.Case
  doctest CaddyDevServer

  test "greets the world" do
    assert CaddyDevServer.hello() == :world
  end
end
