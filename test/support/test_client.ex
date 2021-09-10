defmodule WebSockex.TestClient do
  use WebSockex

  def start(url, state, opts \\ []) do
    WebSockex.start(url, __MODULE__, state, opts)
  end

  def start_link(url, state, opts \\ []) do
    WebSockex.start_link(url, __MODULE__, state, opts)
  end

  def catch_attr(client, atom), do: catch_attr(client, atom, self())

  def catch_attr(client, atom, receiver) do
    attr = "catch_" <> Atom.to_string(atom)
    WebSockex.cast(client, {:set_attr, String.to_atom(attr), receiver})
  end

  def format_status(_opt, [_pdict, %{fail_status: true}]) do
    raise "Failed Status"
  end

  def format_status(_opt, [_pdict, %{non_list_status: true}]) do
    {:data, "Not a list!"}
  end

  def format_status(_opt, [_pdict, %{custom_status: true}]) do
    [{:data, [{"Lemon", :pies}]}]
  end

  def get_conn(pid) do
    WebSockex.cast(pid, {:send_conn, self()})

    receive do
      conn = %WebSockex.Conn{} -> conn
    after
      500 -> raise "Didn't receive a Conn"
    end
  end

  def set_attr(pid, key, val) do
    WebSockex.cast(pid, {:set_attr, key, val})
  end

  def get_state(pid) do
    :ok = WebSockex.cast(pid, {:get_state, self()})

    receive do
      msg -> msg
    after
      200 -> raise "State didn't return after 200ms"
    end
  end

  def handle_connect(_conn, %{connect_badreply: true}), do: :lemons
  def handle_connect(_conn, %{connect_error: true}), do: raise("Connect Error")
  def handle_connect(_conn, %{connect_exit: true}), do: exit("Connect Exit")

  def handle_connect(_conn, %{catch_connect: pid} = args) do
    send(pid, :caught_connect)
    {:ok, args}
  end

  def handle_connect(_conn, %{async_test: true}) do
    receive do
      {:continue_async, pid} ->
        send(pid, :async_test)
        exit("Async Test")
    after
      50 ->
        raise "Async Timeout"
    end
  end

  def handle_connect(conn, state) do
    {:ok, Map.put(state, :conn, conn)}
  end

  def handle_cast({:pid_reply, pid}, state) do
    send(pid, :cast)
    {:ok, state}
  end

  def handle_cast({:set_state, state}, _state), do: {:ok, state}
  def handle_cast({:set_attr, key, attr}, state), do: {:ok, Map.put(state, key, attr)}

  def handle_cast({:get_state, pid}, state) do
    send(pid, state)
    {:ok, state}
  end

  def handle_cast({:send, frame}, state), do: {:reply, frame, state}
  def handle_cast(:close, state), do: {:close, state}
  def handle_cast({:close, code, reason}, state), do: {:close, {code, reason}, state}

  def handle_cast(:self_send, _) do
    WebSockex.send_frame(self(), :ping)
  end

  def handle_cast(:delayed_close, state) do
    receive do
      {:tcp_closed, socket} ->
        send(self(), {:tcp_closed, socket})
        {:close, state}
    end
  end

  def handle_cast({:send_conn, pid}, %{conn: conn} = state) do
    send(pid, conn)
    {:ok, state}
  end

  def handle_cast(:test_reconnect, state) do
    {:close, {4985, "Testing Reconnect"}, state}
  end

  def handle_cast(:bad_frame, state) do
    {:reply, {:haha, "No"}, state}
  end

  def handle_cast(:bad_reply, _), do: :lemon_pie
  def handle_cast(:error, _), do: raise("Cast Error")
  def handle_cast(:exit, _), do: exit("Cast Exit")

  def handle_info({:send, frame}, state), do: {:reply, frame, state}
  def handle_info(:close, state), do: {:close, state}
  def handle_info({:close, code, reason}, state), do: {:close, {code, reason}, state}

  def handle_info({:pid_reply, pid}, state) do
    send(pid, :info)
    {:ok, state}
  end

  def handle_info(:bad_reply, _), do: :lemon_pie
  def handle_info(:error, _), do: raise("Info Error")
  def handle_info(:exit, _), do: exit("Info Exit")

  def handle_ping({:ping, "Bad Reply"}, _), do: :lemon_pie
  def handle_ping({:ping, "Error"}, _), do: raise("Ping Error")
  def handle_ping({:ping, "Exit"}, _), do: exit("Ping Exit")
  def handle_ping({:ping, "Please Reply"}, state), do: {:reply, {:pong, "No"}, state}
  def handle_ping(frame, state), do: super(frame, state)

  # Implicitly test default implementation defined with using through super
  def handle_pong(:pong = frame, %{catch_pong: pid} = state) do
    send(pid, :caught_pong)
    super(frame, state)
  end

  def handle_pong({:pong, msg} = frame, %{catch_pong: pid} = state) do
    send(pid, {:caught_payload_pong, msg})
    super(frame, state)
  end

  def handle_pong({:pong, "Bad Reply"}, _), do: :lemon_pie
  def handle_pong({:pong, "Error"}, _), do: raise("Pong Error")
  def handle_pong({:pong, "Exit"}, _), do: exit("Pong Exit")
  def handle_pong({:pong, "Please Reply"}, state), do: {:reply, {:text, "No"}, state}

  def handle_frame({:binary, msg}, %{catch_binary: pid} = state) do
    send(pid, {:caught_binary, msg})
    {:ok, state}
  end

  def handle_frame({:text, msg}, %{catch_text: pid} = state) do
    send(pid, {:caught_text, msg})
    {:ok, state}
  end

  def handle_frame({:text, "Please Reply"}, state), do: {:reply, {:text, "No"}, state}
  def handle_frame({:text, "Bad Reply"}, _), do: :lemon_pie
  def handle_frame({:text, "Error"}, _), do: raise("Frame Error")
  def handle_frame({:text, "Exit"}, _), do: exit("Frame Exit")

  def handle_disconnect(_, %{disconnect_badreply: true}), do: :lemons
  def handle_disconnect(_, %{disconnect_error: true}), do: raise("Disconnect Error")
  def handle_disconnect(_, %{disconnect_exit: true}), do: exit("Disconnect Exit")

  def handle_disconnect(_, %{catch_init_connect_failure: pid} = state) do
    send(pid, :caught_initial_conn_failure)
    {:ok, state}
  end

  def handle_disconnect(%{attempt_number: 3} = failure_map, %{multiple_reconnect: pid} = state) do
    send(pid, {:stopping_retry, failure_map})
    {:ok, state}
  end

  def handle_disconnect(
        %{attempt_number: attempt} = failure_map,
        %{multiple_reconnect: pid} = state
      ) do
    send(pid, {:retry_connect, failure_map})
    send(pid, {:check_retry_state, %{attempt: attempt, state: state}})
    {:reconnect, Map.put(state, :attempt, attempt)}
  end

  def handle_disconnect(_, %{change_conn_reconnect: pid, good_url: url} = state) do
    uri = URI.parse(url)
    conn = WebSockex.Conn.new(uri)
    send(pid, :retry_change_conn)
    {:reconnect, conn, state}
  end

  def handle_disconnect(%{reason: {:local, 4985, _}}, state) do
    {:reconnect, state}
  end

  def handle_disconnect(
        %{reason: {:remote, :closed}},
        %{catch_disconnect: pid, reconnect: true} = state
      ) do
    send(pid, {:caught_disconnect, :reconnecting})
    {:reconnect, state}
  end

  def handle_disconnect(_, %{reconnect: true} = state) do
    {:reconnect, state}
  end

  def handle_disconnect(
        %{reason: {:remote, :closed} = reason} = map,
        %{catch_disconnect: pid} = state
      ) do
    send(pid, {:caught_disconnect, reason})
    super(map, state)
  end

  def handle_disconnect(%{reason: {_, :normal}} = map, %{catch_disconnect: pid} = state) do
    send(pid, :caught_disconnect)
    super(map, state)
  end

  def handle_disconnect(%{reason: {_, code, reason}}, %{catch_disconnect: pid} = state) do
    send(pid, {:caught_disconnect, code, reason})
    {:ok, state}
  end

  def handle_disconnect(_, %{catch_disconnect: pid} = state) do
    send(pid, :caught_disconnect)
    {:ok, state}
  end

  def handle_disconnect(_, state), do: {:ok, state}

  def terminate({:local, :normal}, %{catch_terminate: pid}),
    do: send(pid, :normal_close_terminate)

  def terminate(_, %{catch_terminate: pid}), do: send(pid, :terminate)
  def terminate(_, _), do: :ok
end
