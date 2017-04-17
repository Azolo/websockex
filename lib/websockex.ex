defmodule WebSockex do
  use Application

  # Start as an OTP application to set URI default sockets and start ssl and
  # crypto
  @doc """
  Sets the `ws` and `wss` default ports for the `URI` module.
  """
  def start(_type, _args) do
    unless URI.default_port("ws"), do: URI.default_port("ws", 80)
    unless URI.default_port("wss"), do: URI.default_port("wss", 443)

    # Start an empty supervisor for OTP
    Supervisor.start_link([], [strategy: :one_for_one, name: WebSockex.Supervisor])
  end
end
