defmodule WebSockex.TestServer do
  Module.register_attribute(__MODULE__, :dialyzer, persist: true)
  use Plug.Router

  @certfile Path.join([__DIR__, "priv", "websockex.cer"])
  @keyfile Path.join([__DIR__, "priv", "websockex.key"])
  @cacert Path.join([__DIR__, "priv", "websockexca.cer"])
          |> File.read!()
          |> :public_key.pem_decode()

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

    case Plug.Adapters.Cowboy.http(__MODULE__, [], opts) do
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

    case Plug.Adapters.Cowboy.https(__MODULE__, [], opts) do
      {:ok, _} ->
        {:ok, {ref, url}}

      {:error, :eaddrinuse} ->
        require Logger
        Logger.error("Address #{port} in use!")
        start_https(pid)
    end
  end

  def new_conn_mode(socket_pid, mode) do
    ref = make_ref()
    send(socket_pid, {:mode, mode, ref, self()})

    receive do
      {^ref, :ok} ->
        :ok
    end
  end

  def shutdown(ref) do
    Plug.Adapters.Cowboy.shutdown(ref)
  end

  def receive_socket_pid do
    receive do
      pid when is_pid(pid) ->
        pid
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
    unless Process.whereis(__MODULE__), do: start_ports_agent()

    Agent.get_and_update(__MODULE__, fn port -> {port, port + 1} end)
  end

  defp start_ports_agent do
    Agent.start(fn -> Enum.random(50_000..63_000) end, name: __MODULE__)
  end
end

defmodule WebSockex.TestSocket do
  @behaviour :cowboy_websocket

  @impl true
  def init(req, [{peer_pid, agent_pid}]) do
    state = %{pid: peer_pid, agent_pid: agent_pid}

    case Agent.get(agent_pid, fn x -> x end) do
      :ok ->
        {:cowboy_websocket, req, state}

      {:code, int} when is_integer(int) ->
        :cowboy_req.reply(int, req)
        {:shutdown, req, :tests_are_fun}

      :connection_wait ->
        send(peer_pid, self())
        wait_for_signal(:connection_continue)
        {:cowboy_websocket, req, state}

      :immediate_reply ->
        {:cowboy_websocket, req, {:immediate_reply, state}}
    end
  end

  defp wait_for_signal(signal) do
    receive do
      ^signal -> :ok
    end
  end

  @impl true
  def websocket_init({:immediate_reply, state}) do
    send(state.pid, self())
    frame = {:text, "Immediate Reply"}
    {[frame], state}
  end

  def websocket_init(state) do
    send(state.pid, self())
    {:ok, state}
  end

  @impl true
  def terminate(:remote, _req, state) do
    send(state.pid, :normal_remote_closed)
    :ok
  end

  def terminate({:remote, close_code, reason}, _, state) do
    send(state.pid, {close_code, reason})
    :ok
  end

  def terminate(_, _, _),
    do: :ok

  @impl true
  def websocket_handle({:binary, msg}, state) do
    send(state.pid, :erlang.binary_to_term(msg))
    {:ok, state}
  end

  def websocket_handle(:ping, state),
    do: {:ok, state}

  def websocket_handle(:pong, state) do
    send(state.pid, :received_pong)
    {:ok, state}
  end

  def websocket_handle({:pong, payload}, %{ping_payload: ping_payload} = state)
      when payload == ping_payload do
    send(state.pid, :received_payload_pong)
    {:ok, state}
  end

  @impl true
  def websocket_info(:stall, _),
    do: Process.sleep(:infinity)

  def websocket_info(:send_ping, state),
    do: {:reply, :ping, state}

  def websocket_info(:send_payload_ping, state) do
    payload = "Llama and Lambs"
    {:reply, {:ping, payload}, Map.put(state, :ping_payload, payload)}
  end

  def websocket_info(:close, state),
    do: {:reply, :close, state}

  def websocket_info({:close, code, reason}, state),
    do: {:reply, {:close, code, reason}, state}

  def websocket_info({:send, frame}, state),
    do: {:reply, frame, state}

  def websocket_info({:mode, mode, ref, pid}, state) do
    :ok = set_mode(state, mode)
    send(pid, {ref, :ok})

    {:ok, state}
  end

  def websocket_info(:shutdown, state),
    do: {:shutdown, state}

  defp set_mode(%{agent_pid: agent}, mode),
    do: Agent.update(agent, fn _ -> mode end)
end
