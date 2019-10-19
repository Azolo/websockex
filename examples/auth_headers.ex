defmodule AuthHeaders do
  use WebSockex

  @moduledoc ~S"""
  Sample usage connecting to server using authorization.
  You can specify `extra_headers` in as fourth parameter to
  `WebSockex.start_link/4` which then will be used build
  connection to websocket server.
  """
     
  def start_link(url, state) do
    extra_headers = [
      {"Authorization", "JWT ..."}
    ]

    WebSockex.start_link(url, __MODULE__, state, extra_headers: extra_headers)
  end
end
