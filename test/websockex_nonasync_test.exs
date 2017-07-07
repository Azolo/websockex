defmodule WebSockexNonasyncTest do
  use ExUnit.Case

  defmodule DummyClient do
    use WebSockex
  end

  test "supplies a ApplicationError when the application is not started" do
    Application.stop(:websockex)
    on_exit fn -> Application.ensure_all_started(:websockex) end

    refute Application.started_applications |> List.keyfind(:websockex, 0)

    :ets.delete(:elixir_config, {:uri, "ws"})
    refute URI.default_port("ws")

    assert WebSockex.start_link("ws://fakeurl", DummyClient, %{}) ==
      {:error, %WebSockex.ApplicationError{reason: :not_started}}
  end
end
