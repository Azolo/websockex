defmodule WebSockex.TestServer do
  use Plug.Router

  plug :match
  plug :dispatch

  match _ do
    send_resp(conn, 200, "Hello from plug")
  end

  def start(pid) when is_pid(pid) do
    ref = make_ref()
    port = get_port()
    url = "ws://localhost:#{port}/ws"
    case Plug.Adapters.Cowboy.http(__MODULE__, [], [dispatch: dispatch(pid), port: port, ref: ref]) do
      {:ok, _} ->
        {:ok, {ref, url}}
      {:error, :eaddrinuse} ->
        IO.puts "Address #{port} in use!"
        start(pid)
    end
  end

  def shutdown(ref) do
    Plug.Adapters.Cowboy.shutdown(ref)
  end

  def receive_socket_pid do
    receive do
      pid when is_pid(pid) -> pid
      _ -> receive_socket_pid()
    after
      500 -> raise "No Server Socket pid"
    end
  end

  defp dispatch(pid) do
    [{:_, [{"/ws", WebSockex.TestSocket, [pid]}]}]
  end

  defp get_port do
    unless Process.whereis(__MODULE__), do: start_ports_agent()

    Agent.get_and_update(__MODULE__, fn(port) -> {port, port + 1} end)
  end

  defp start_ports_agent do
    Agent.start(fn -> Enum.random(50_000..63_000) end, name: __MODULE__)
  end
end

defmodule WebSockex.TestSocket do
  @behaviour :cowboy_websocket_handler

  def init(_, _, _) do
    {:upgrade, :protocol, :cowboy_websocket}
  end

  def websocket_init(_, req, [pid]) do
    send(pid, self())
    {:ok, req, %{pid: pid, s: 0}}
  end

  def websocket_terminate({:remote, :closed}, _, state) do
    send(state.pid, :normal_remote_closed)
  end
  def websocket_terminate(_, _, _) do
    :ok
  end

  def websocket_handle({:binary, unquote(:erlang.term_to_binary(:cast_msg))}, req, state) do
    send(state.pid, :cast_msg)
    {:ok, req, state}
  end

  def websocket_info(:ping, req, state), do: {:reply, :ping, req, state}
  def websocket_info(:payload_ping, req, state), do: {:reply, {:ping, "Llama and Lambs"}, req, state}
  def websocket_info(_, req, state), do: {:ok, req, state}
end
