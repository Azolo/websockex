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

  def handle_cast({:send, {type, msg} = frame}, state) do
    IO.puts "Sending #{type} frame with payload: #{msg}"
    {:reply, frame, state}
  end
end
```

See the `examples/` directory for other examples or take a look at the [documentation][docs].

## Installation

Add `websockex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:websockex, "~> 0.4.3"}]
end
```

### With Elixir releases prior to version  1.4

Ensure `websockex` is started before your application:

```elixir
def application do
  [applications: [:websockex]]
end
```

## Why WebSockex?

WebSockex was conceived after trying other libraries and realizing that I needed something tested, that actually
implemented the spec, provided information about the connection, and could fit into a supervision tree. There was
nothing that really fit into all those categories, so WebSockex was created.

There are other libraries out there can fit into some of the categories, but I consider WebSockex the best option if
you want a callback inspired approach where most of the protocol workings are abstracted out of your way.

If you are afraid that WebSockex isn't stable enough or have some other problem with it that you don't feel like
telling me about, then I would suggest the excellent [`gun` library][gun_hex]. It's a bit harder to use, and requires
some knowledge of the spec. However it is an excellent library.

[gun_hex]: https://hex.pm/packages/gun

## Supervision and Linking

A WebSockex based process is a easily able to fit into any supervision tree. It supports all the necessary capabilites
to do so. In addition, it supports the `Supervisor` children format introduced in Elixir 1.5. So in any version of
Elixir after 1.5, you can simply do:

```elixir
defmodule MyApp.Client do
  use WebSockex

  def start_link(state) do
    WebSockex.start_link("ws://myapp.ninja", __MODULE__, state)
  end
end

defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {MyApp.Client, ["WebSockex is Great"]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

See the Supervision section in the `WebSockex` module documentation for more details on how this works.

WebSockex also supports both linked(`start_link/3`) and unlinked(`start/3`) processes.

```elixir
iex> {:ok, pid} = WebSockex.start_link(url, __MODULE__, state)
iex> {:ok, pid} = WebSockex.start(url, __MODULE__, state)
```

However, the recommendation is to always use `start_link/3` and if necessary trap exits.

This is because `start/3` creates a detached process and has the capability to produce zombie processes outside of any
application tree. This is generally a good piece of advice for any process, however since a module using WebSockex
bevhaviour can be written as a self-sustaining tcp connection. I feel like it is even more important to express this
particular piece of advice here.

## Telemetry

Websockex clients emit the following telemetry events:

* `[:websockex, :connect]`
* `[:websockex, :disconnect]`
* `[:websockex, :frame, :received]`
* `[:websockex, :frame, :sent]`
* `[:websockex, :terminate]`

For all these events, the measurements is `%{time: System.system_time()}` and they all share common metadata as a map containing the `:conn`, `:pid`, `:module` keys. For frame events, the metadata also contains the `:frame` key. For disconnections and terminations, it will contain the `:reason` key. 


## Tips
### Terminating with :normal after an Exceptional Close or Error

Usually you'll want to negotiate and handle any abnormal close event or error leading to it, as per WS Spec, but there might be cases where you simply want the socket to exit as if it was a normal event, even if it was abruptly closed or another exception was raised. In those cases you can define the terminate callback and return `exit(:normal)` from it.
```elixir
def terminate(reason, state) do
    IO.puts(\nSocket Terminating:\n#{inspect reason}\n\n#{inspect state}\n")
    exit(:normal)
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

[special_process]: http://erlang.org/doc/design_principles/spec_proc.html
[docs]: https://hexdocs.pm/websockex
