defmodule WebSockexTest do
  use ExUnit.Case
  doctest WebSockex

  test "Set URI default ports for ws and wss" do
    assert URI.default_port("ws") == 80
    assert URI.default_port("wss") == 443
  end
end
