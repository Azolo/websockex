# WebSockex

[![Build Status](https://travis-ci.org/Azolo/websockex.svg?branch=master)](https://travis-ci.org/Azolo/websockex)
[![Build status](https://ci.appveyor.com/api/projects/status/jtat5j0vkh6o2ypy?svg=true)](https://ci.appveyor.com/project/Azolo/websockex)

An Elixir Websocket Client.

A simple implementation could be

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

Add `websockex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:websockex, "~> 0.4.0"}]
end
```

### With Elixir releases prior to version  1.4

Ensure `websockex` is started before your application:

```elixir
def application do
  [applications: [:websockex]]
end
```

## Debugging

WebSockex supports the debugging mechanism for [OTP Special Processes][special_process] provided through the `:sys` module.

Since WebSockex rolls its own Special Process implementation, it's able to provide a lot more information than a regular
`GenServer`.

If, for example, I enable tracing with `EchoClient` from the examples (with `Logger` off), I would get this:

```elixir
iex> {:ok, pid} = EchoClient.start_link(debug: [:trace])
*DBG* #PID<0.371.0> attempting to connect
*DBG* #PID<0.371.0> sucessfully connected
{:ok, #PID<0.371.0>}
iex> EchoClient.echo(pid, "Hello")
*DBG* #PID<0.371.0> sending frame: {:text, "Hello"}
:ok
*DBG* #PID<0.371.0> received frame: {:text, "Hello"}
*DBG* #PID<0.371.0> received frame: :ping
*DBG* #PID<0.371.0> replying from :handle_ping with :pong
iex> EchoClient.echo(pid, "Close the things!")
*DBG* #PID<0.371.0> sending frame: {:text, "Close the things!"}
:ok
*DBG* #PID<0.371.0> received frame: {:text, "Close the things!"}
*DBG* #PID<0.371.0> closing with local reason: {:local, :normal}
*DBG* #PID<0.371.0> sending close frame: {:local, :normal}
*DBG* #PID<0.371.0> forcefully closed the connection because the server was taking too long close
```

You could also enable tracing after a process has started like this:

```elixir
iex> {:ok, pid} = EchoClient.start_link()
iex> :sys.trace(pid, true)
:ok
iex> EchoClient.echo(pid, "Hi")
*DBG* #PID<0.379.0> sending frame: {:text, "Hi"}
:ok
*DBG* #PID<0.379.0> received frame: {:text, "Hi"}
```

## Supervision and Linking

You can start a supervisioned WebSockex connection by using the regular **start_link/3**:
```elixir
iex> {:ok, pid} = WebSockex.start_link(url, __MODULE__, state)
```
Or an unlinked one with **start/3**:
```elixir
iex> {:ok, pid} = WebSockex.start(url, __MODULE__, state)
```
*Note* - when using **start/3** from supervised processes there's a possibility of ending up with zombie websockex processes since they're not linked to the calling process, in case the calling process is restarted the websockex process will be unaware of it - in this case you'll usually want to trap exits in order to correctly close the websockex process.

## Tips
### Terminating with :normal after an Exceptional Close or Error

Usually you'll want to negotiate and handle any abnormal close event or error leading to it, as per WS Spec, but there might be cases where you simply want the socket to exit as if it was a normal event, even if it was abruptly closed or another exception was raised. In those cases you can define the terminate callback and return `exit(:normal)` from it.
```elixir
def terminate(reason, state) do
    IO.puts(\nSocket Terminating:\n#{inspect reason}\n\n#{inspect state}\n")
    exit(:normal)
end
```

[special_process]: http://erlang.org/doc/design_principles/spec_proc.html
[docs]: https://hexdocs.pm/websockex
