defmodule WebSockex.TestServer do
  Module.register_attribute(__MODULE__, :dialyzer, persist: true)
  @moduledoc false
  use Plug.Router
  alias Plug.Adapters.Cowboy
  @certfile Path.join([__DIR__, "priv", "websockex.cer"])
  @keyfile Path.join([__DIR__, "priv", "websockex.key"])
  @cacert Path.join([__DIR__, "priv", "websockexca.cer"]) |> File.read!() |> :public_key.pem_decode()

  plug(:match)
  plug(:dispatch)

  match _ do
    send_resp(conn, 200, "Hello from plug")
  end

  def start(pid) when is_pid(pid) do
    ref = make_ref()
    port = get_port()
    {:ok, agent_pid} = Agent.start_link(fn -> :ok end)
    url = "ws://localhost:#{port}/ws"

    opts = [dispatch: dispatch({pid, agent_pid}), port: port, ref: ref]

    case Cowboy.http(__MODULE__, [], opts) do
      {:ok, _} ->
        {:ok, {ref, url}}

      {:error, :eaddrinuse} ->
        start(pid)
    end
  end

  def start_https(pid) do
    ref = make_ref()
    port = get_port()
    url = "wss://localhost:#{port}/ws"
    {:ok, agent_pid} = Agent.start_link(fn -> :ok end)

    opts = [
      dispatch: dispatch({pid, agent_pid}),
      certfile: @certfile,
      keyfile: @keyfile,
      port: port,
      ref: ref
    ]

    case Cowboy.https(__MODULE__, [], opts) do
      {:ok, _} ->
        {:ok, {ref, url}}

      {:error, :eaddrinuse} ->
        require Logger
        _ = Logger.error("Address #{port} in use!")
        start_https(pid)
    end
  end

  def shutdown(ref), do: Cowboy.shutdown(ref)

  def receive_socket_pid do
    receive do
      pid when is_pid(pid) -> pid
    after
      500 -> raise "No Server Socket pid"
    end
  end

  def cacerts do
    [{:Certificate, cert, _}] = @cacert
    [cert]
  end

  defp dispatch(tuple) do
    [{:_, [{"/ws", WebSockex.TestSocket, [tuple]}]}]
  end

  defp get_port do
    _ = unless Process.whereis(__MODULE__), do: start_ports_agent()

    Agent.get_and_update(__MODULE__, fn port -> {port, port + 1} end)
  end

  defp start_ports_agent do
    Agent.start(fn -> Enum.random(50_000..63_000) end, name: __MODULE__)
  end
end

defmodule WebSockex.TestSocket do
  @behaviour :cowboy_websocket

  def init(req, [{test_pid, agent_pid}] = state) do
    case Agent.get(agent_pid, fn x -> x end) do
      :ok ->
        {:cowboy_websocket, req, state}

      int when is_integer(int) ->
        _ = :cowboy_req.reply(int, req)
        {:shutdown, req, :tests_are_fun}

      :connection_wait ->
        send(test_pid, self())

        receive do
          :connection_continue ->
            {:cowboy_websocket, req, state}
        end
    end
  end

  def websocket_init([{test_pid, agent_pid}]) do
    send(test_pid, self())
    {:ok, %{pid: test_pid, agent_pid: agent_pid}}
  end

  def terminate(:remote, _, state) do
    send(state.pid, :normal_remote_closed)
  end

  def terminate({:remote, :closed}, _, state) do
    send(state.pid, :normal_remote_closed)
  end

  def terminate({:remote, close_code, reason}, _, state) do
    send(state.pid, {close_code, reason})
  end

  def terminate(_, _, _) do
    :ok
  end

  def websocket_handle({:binary, msg}, state) do
    send(state.pid, :erlang.binary_to_term(msg))
    {:ok, state}
  end

  def websocket_handle({:ping, _}, state), do: {:ok, state}
  def websocket_handle(:ping, state), do: {:ok, state}

  def websocket_handle(:pong, state) do
    send(state.pid, :received_pong)
    {:ok, state}
  end

  def websocket_handle({:pong, payload}, %{ping_payload: ping_payload} = state)
      when payload == ping_payload do
    send(state.pid, :received_payload_pong)
    {:ok, state}
  end

  def websocket_info(:stall, _) do
    Process.sleep(:infinity)
  end

  def websocket_info(:send_ping, state), do: {:reply, :ping, state}

  def websocket_info(:send_payload_ping, state) do
    payload = "Llama and Lambs"
    {:reply, {:ping, payload}, Map.put(state, :ping_payload, payload)}
  end

  def websocket_info(:close, state), do: {:reply, :close, state}

  def websocket_info({:close, reason}, state) do
    {:reply, {:close, reason}, state}
  end

  def websocket_info({:close, code, reason}, state) do
    {:reply, {:close, code, reason}, state}
  end

  def websocket_info({:send, frame}, state) do
    {:reply, frame, state}
  end

  def websocket_info({:set_code, code}, state) do
    Agent.update(state.agent_pid, fn _ -> code end)
    {:ok, state}
  end

  def websocket_info(:connection_wait, state) do
    Agent.update(state.agent_pid, fn _ -> :connection_wait end)
    {:ok, state}
  end

  def websocket_info(:immediate_reply, state) do
    Agent.update(state.agent_pid, fn _ -> :immediate_reply end)
    {:ok, state}
  end

  def websocket_info(:shutdown, state) do
    {:shutdown, state}
  end

  def websocket_info(_, state), do: {:ok, state}
end
