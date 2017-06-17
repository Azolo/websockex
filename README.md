# WebSockex

[![Build Status](https://travis-ci.org/Azolo/websockex.svg?branch=master)](https://travis-ci.org/Azolo/websockex)
[![Build status](https://ci.appveyor.com/api/projects/status/jtat5j0vkh6o2ypy?svg=true)](https://ci.appveyor.com/project/Azolo/websockex)

An Elixir Websocket Client.

A simple implemenation would be

```elixir
defmodule WebSocketExample do
  use WebSockex

  def start_link(url, state) do
    WebSockex.start_link(url, __MODULE__, state)
  end

  def handle_frame({type, msg}, state) do
    IO.puts "Received Message - Type: #{inspect type} -- Message: #{inspect msg}"
    {:ok, state}
  end
end
```

See the `examples/` directory for other examples or take a look at the [documentation][docs].

## Installation

1. Add `websockex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:websockex, "~> 0.3.0"}]
end
```

2. Ensure `websockex` is started before your application:

```elixir
def application do
  [applications: [:websockex]]
end
```

[docs]: https://hexdocs.pm/websockex
