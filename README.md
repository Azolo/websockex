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

#### start_link/3 && start/3 

You can start a supervisioned WebSockex connection by using the regular **start_link/3**:

```elixir
iex> {:ok, pid} = WebSockex.start_link(url, __MODULE__, state)
```

And an unsupervisioned one (meaning it won't try to re-establish the connection on an exceptional close) with **start/3**:

```elixir
iex> {:ok, pid} = WebSockex.start(url, __MODULE__, state)
```

This can be useful if you have don't want the socket to automatically try reconnection, you have no need for the built-in supervision or if you're implementing your own supervision strategy.


#### Callbacks
###### terminate/2

This callback allows you to handle different events related to the WebSocket termination. WebSockex will provide you a 2-element tuple for this event, e.g. `{:remote, :closed}`, and while usually you'll want to negotiate and handle the close event, as per WS Spec, there might be cases where you simply want the socket to exit as if it was a normal event. In those case you can return `exit(:normal)` and no exception will be raised

```elixir
def terminate(reason, state) do
    IO.puts(\nSocket Terminating:\n#{inspect reason}\n\n#{inspect state}\n")
    exit(:normal)
end
```


#### Example Usage With a Chrome Remote Debugging Enabled Instance (or driver), and using Poison to decode/encode the remote-protocol message passing (assuming you have started chrome with a remote debugging port, and have the WebSocket address for the page/tab in question), closing chrome would cause {:remote, :closed} to be raised, but in this case we really don't care:

```elixir
defmodule ChromeDebugger do
     use WebSockex
     
     def start(url, state) do
       {:ok, pid} = WebSockex.start(url, __MODULE__, state)
       WebSockex.send_frame(pid, {:text, Poison.encode!(%{id: 1, method: "Network.enable", params: %{}})})
       WebSockex.send_frame(pid, {:text, Poison.encode!(%{id: 2, method: "Runtime.enable", params: %{}})})
       WebSockex.send_frame(pid, {:text, Poison.encode!(%{id: 3, method: "Page.enable", params: %{}})})
       {:ok, pid}
     end

     def terminate(reason, state) do
       exit(:normal)
     end

     def handle_frame({_type, msg}, state) do
       case Poison.decode(msg) do
         {:error, error} ->
           Logger.debug(inspect msg)
           Logger.error(inspect error)
         {:ok, message} ->
           case message["method"] do
             "Network.webSocketFrameReceived" ->
                with true <- message["params"]["response"]["opcode"] == 1,
                   message_pl <- message["params"]["response"]["payloadData"]
                do
                  IO.inspect(message_pl)
                else
                  _ -> :ok
                end
              _ -> :ok
           end
        end
        {:ok, state}
     end
end
```

And there you go, you now have a socket listening to the chrome remote dev-tools notifications.









[special_process]: http://erlang.org/doc/design_principles/spec_proc.html
[docs]: https://hexdocs.pm/websockex
