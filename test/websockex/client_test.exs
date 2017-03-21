defmodule WebSockex.ClientTest do
  use ExUnit.Case, async: true

  @basic_server_frame <<1::1, 0::3, 1::4, 0::1, 5::7, "Hello"::utf8>>

  defmodule TestClient do
    use WebSockex.Client

    def start_link(url, state, opts \\ []) do
      WebSockex.Client.start_link(url, __MODULE__, state, opts)
    end

    def catch_attr(client, atom, receiver) do
      attr = "catch_" <> Atom.to_string(atom)
      WebSockex.Client.cast(client, {:set_attr, String.to_atom(attr), receiver})
    end

    def init(%{catch_init: pid} = args, _conn) do
      send(pid, :caught_init)
      {:ok, args}
    end
    def init(args, conn) do
      {:ok, Map.put(args, :conn, conn)}
    end

    def handle_cast({:pid_reply, pid}, state) do
      send(pid, :cast)
      {:ok, state}
    end
    def handle_cast({:set_state, state}, _state), do: {:ok, state}
    def handle_cast(:error, _), do: raise "an error"
    def handle_cast({:set_attr, key, attr}, state), do: {:ok, Map.put(state, key, attr)}
    def handle_cast({:get_state, pid}, state) do
      send(pid, state)
      {:ok, state}
    end
    def handle_cast({:send, frame}, state), do: {:reply, frame, state}
    def handle_cast(:close, state), do: {:close, state}
    def handle_cast({:close, code, reason}, state), do: {:close, {code, reason}, state}
    def handle_cast({:send_conn, pid}, %{conn: conn} = state) do
      send pid, conn
      {:ok, state}
    end
    def handle_cast(:test_reconnect, state) do
      {:close, {4985, "Testing Reconnect"}, state}
    end

    def handle_info({:send, frame}, state), do: {:reply, frame, state}
    def handle_info(:close, state), do: {:close, state}
    def handle_info({:close, code, reason}, state), do: {:close, {code, reason}, state}
    def handle_info({:pid_reply, pid}, state) do
      send(pid, :info)
      {:ok, state}
    end
    def handle_info(:bad_reply, _) do
      :lemon_pie
    end

    # Implicitly test default implementation defined with using through super
    def handle_pong(:pong = frame, %{catch_pong: pid} = state) do
      send(pid, :caught_pong)
      super(frame, state)
    end
    def handle_pong({:pong, msg} = frame, %{catch_pong: pid} = state) do
      send(pid, {:caught_payload_pong, msg})
      super(frame, state)
    end

    def handle_frame({:binary, msg}, %{catch_binary: pid} = state) do
      send(pid, {:caught_binary, msg})
      {:ok, state}
    end
    def handle_frame({:text, msg}, %{catch_text: pid} = state) do
      send(pid, {:caught_text, msg})
      {:ok, state}
    end

    def handle_disconnect({:local, 4985, _}, state) do
      {:reconnect, state}
    end
    def handle_disconnect({_, :normal} = reason, %{catch_disconnect: pid} = state) do
      send(pid, :caught_disconnect)
      super(reason, state)
    end
    def handle_disconnect({_, code, reason}, %{catch_disconnect: pid} = state) do
      send(pid, {:caught_disconnect, code, reason})
      {:ok, state}
    end
    def handle_disconnect(_, state), do: {:ok, state}

    def terminate({:local, :normal}, %{catch_terminate: pid}), do: send(pid, :normal_close_terminate)
    def terminate(_, %{catch_terminate: pid}), do: send(pid, :terminate)
    def terminate(_, _), do: :ok
  end

  setup do
    {:ok, {server_ref, url}} = WebSockex.TestServer.start(self())

    on_exit fn -> WebSockex.TestServer.shutdown(server_ref) end

    {:ok, pid} = TestClient.start_link(url, %{})
    server_pid = WebSockex.TestServer.receive_socket_pid

    [pid: pid, url: url, server_pid: server_pid]
  end

  test "can connect to secure server" do
    {:ok, {server_ref, url}} = WebSockex.TestServer.start_https(self())

    on_exit fn -> WebSockex.TestServer.shutdown(server_ref) end

    {:ok, pid} = TestClient.start_link(url, %{}, cacerts: WebSockex.TestServer.cacerts)
    server_pid = WebSockex.TestServer.receive_socket_pid

    TestClient.catch_attr(pid, :pong, self())

    # Test server -> client ping
    send server_pid, :send_ping
    assert_receive :received_pong

    # Test client -> server ping
    WebSockex.Client.cast(pid, {:send, :ping})
    assert_receive :caught_pong
  end

  test "handle changes state", context do
    rand_number = :rand.uniform(1000)

    WebSockex.Client.cast(context.pid, {:get_state, self()})
    refute_receive ^rand_number

    WebSockex.Client.cast(context.pid, {:set_state, rand_number})
    WebSockex.Client.cast(context.pid, {:get_state, self()})
    assert_receive ^rand_number
  end

  test "can receive partial frames", context do
    WebSockex.Client.cast(context.pid, {:send_conn, self()})
    TestClient.catch_attr(context.pid, :text, self())
    assert_receive conn = %WebSockex.Conn{}

    <<part::bits-size(14), rest::bits>> = @basic_server_frame

    send(context.pid, {conn.transport, conn.socket, part})
    send(context.pid, {conn.transport, conn.socket, rest})

    assert_receive {:caught_text, "Hello"}
  end

  test "can receive multiple frames", context do
    WebSockex.Client.cast(context.pid, {:send_conn, self()})
    TestClient.catch_attr(context.pid, :text, self())
    assert_receive conn = %WebSockex.Conn{}
    :inet.setopts(conn.socket, active: false)

    send context.server_pid, {:send, {:text, "Hello"}}
    send context.server_pid, {:send, {:text, "Bye"}}

    :inet.setopts(conn.socket, active: true)

    assert_receive {:caught_text, "Hello"}
    assert_receive {:caught_text, "Bye"}
  end

  test "errors when receiving two fragment starts", context do
    Process.unlink(context.pid)
    WebSockex.Client.cast(context.pid, {:send_conn, self()})
    assert_receive conn = %WebSockex.Conn{}
    fragment = <<0::1, 0::3, 1::4, 0::1, 2::7, "He"::utf8>>

    send(context.pid, {conn.transport, conn.socket, fragment})
    send(context.pid, {conn.transport, conn.socket, fragment})

    assert_receive {1002, "Endpoint tried to start a fragment without finishing another"}
  end

  test "errors with a continuation and no fragment", context do
    Process.unlink(context.pid)
    WebSockex.Client.cast(context.pid, {:send_conn, self()})
    assert_receive conn = %WebSockex.Conn{}
    fragment = <<0::1, 0::3, 0::4, 0::1, 4::7, "Blah"::utf8>>

    send(context.pid, {conn.transport, conn.socket, fragment})

    assert_receive {1002, "Endpoint sent a continuation frame without starting a fragment"}
  end

  test "can receive text fragments", context do
    WebSockex.Client.cast(context.pid, {:send_conn, self()})
    TestClient.catch_attr(context.pid, :text, self())
    assert_receive conn = %WebSockex.Conn{}

    first = <<0::1, 0::3, 1::4, 0::1, 2::7, "He"::utf8>>
    second = <<0::1, 0::3, 0::4, 0::1, 2::7, "ll"::utf8>>
    final = <<1::1, 0::3, 0::4, 0::1, 1::7, "o"::utf8>>

    send(context.pid, {conn.transport, conn.socket, first})
    send(context.pid, {conn.transport, conn.socket, second})
    send(context.pid, {conn.transport, conn.socket, final})

    assert_receive {:caught_text, "Hello"}
  end

  test "can receive binary fragments", context do
    WebSockex.Client.cast(context.pid, {:send_conn, self()})
    TestClient.catch_attr(context.pid, :binary, self())
    assert_receive conn = %WebSockex.Conn{}
    binary = :erlang.term_to_binary(:hello)

    <<first_bin::bytes-size(2), second_bin::bytes-size(2), rest::bytes>> = binary
    len = byte_size(rest)

    first = <<0::1, 0::3, 2::4, 0::1, 2::7, first_bin::bytes>>
    second = <<0::1, 0::3, 0::4, 0::1, 2::7, second_bin::bytes>>
    final = <<1::1, 0::3, 0::4, 0::1, len::7, rest::bytes>>

    send(context.pid, {conn.transport, conn.socket, first})
    send(context.pid, {conn.transport, conn.socket, second})
    send(context.pid, {conn.transport, conn.socket, final})

    assert_receive {:caught_binary, ^binary}
  end

  describe "handle_cast callback" do
    test "is called", context do
      WebSockex.Client.cast(context.pid, {:pid_reply, self()})

      assert_receive :cast
    end

    test "can reply with a message", context do
      message = :erlang.term_to_binary(:cast_msg)
      WebSockex.Client.cast(context.pid, {:send, {:binary, message}})

      assert_receive :cast_msg
    end

    test "can close the connection", context do
      WebSockex.Client.cast(context.pid, :close)

      assert_receive :normal_remote_closed
    end

    test "can close the connection with a code and a message", context do
      Process.flag(:trap_exit, true)
      WebSockex.Client.cast(context.pid, {:close, 4012, "Test Close"})

      assert_receive {:EXIT, _, {:local, 4012, "Test Close"}}
      assert_receive {4012, "Test Close"}
    end
  end

  describe "init callback" do
    test "get called after successful connection", context do
      {:ok, _pid} = TestClient.start_link(context.url, %{catch_init: self()})

      assert_receive :caught_init
    end
  end

  describe "handle_frame" do
    test "can handle a binary frame", context do
      TestClient.catch_attr(context.pid, :binary, self())
      binary = :erlang.term_to_binary(:hello)
      send(context.server_pid, {:send, {:binary, binary}})

      assert_receive {:caught_binary, ^binary}
    end

    test "can handle a text frame", context do
      TestClient.catch_attr(context.pid, :text, self())
      text = "Murky is green"
      send(context.server_pid, {:send, {:text, text}})

      assert_receive {:caught_text, ^text}
    end
  end

  describe "handle_info callback" do
    test "is called", context do
      send(context.pid, {:pid_reply, self()})

      assert_receive :info
    end

    test "can reply with a message", context do
      message = :erlang.term_to_binary(:info_msg)
      send(context.pid, {:send, {:binary, message}})

      assert_receive :info_msg
    end

    test "can close the connection normally", context do
      send(context.pid, :close)

      assert_receive :normal_remote_closed
    end

    test "can close the connection with a code and a message", context do
      Process.flag(:trap_exit, true)
      send(context.pid, {:close, 4012, "Test Close"})

      assert_receive {:EXIT, _, {:local, 4012, "Test Close"}}
      assert_receive {4012, "Test Close"}
    end
  end

  describe "terminate callback" do
    setup context do
      TestClient.catch_attr(context.pid, :terminate, self())
    end

    test "executes in a handle_info error", context do
      Process.unlink(context.pid)
      send(context.pid, :bad_reply)

      assert_receive :terminate
    end

    test "executes in handle_cast error", context do
      Process.unlink(context.pid)
      WebSockex.Client.cast(context.pid, :error)

      assert_receive :terminate
    end

    test "executes in a frame close", context do
      WebSockex.Client.cast(context.pid, :close)

      assert_receive :normal_close_terminate
    end
  end

  describe "handle_ping callback" do
    test "can handle a ping frame", context do
      send(context.server_pid, :send_ping)

      assert_receive :received_pong
    end

    test "can handle a ping frame with a payload", context do
      send(context.server_pid, :send_payload_ping)

      assert_receive :received_payload_pong
    end
  end

  describe "handle_pong callback" do
    test "can handle a pong frame", context do
      TestClient.catch_attr(context.pid, :pong, self())
      WebSockex.Client.cast(context.pid, {:send, :ping})

      assert_receive :caught_pong
    end

    test "can handle a pong frame with a payload", context do
      TestClient.catch_attr(context.pid, :pong, self())
      WebSockex.Client.cast(context.pid, {:send, {:ping, "bananas"}})

      assert_receive {:caught_payload_pong, "bananas"}
    end
  end

  describe "handle_disconnect callback" do
    setup context do
      Process.unlink(context.pid)
      TestClient.catch_attr(context.pid, :disconnect, self())
    end

    test "is invoked when receiving a close frame", context do
      send(context.server_pid, :close)

      assert_receive :caught_disconnect, 750
    end

    test "is invoked when receiving a close frame with a payload", context do
      send(context.server_pid, {:close, 4025, "Testing"})

      assert_receive {:caught_disconnect, 4025, "Testing"}, 750
    end

    test "is invoked when sending a close frame", context do
      WebSockex.Client.cast(context.pid, :close)

      assert_receive :caught_disconnect, 750
    end

    test "is invoked when sending a close frame with a payload", context do
      WebSockex.Client.cast(context.pid, {:close, 4025, "Testing"})

      assert_receive {:caught_disconnect, 4025, "Testing"}, 750
    end

    test "can reconnect to the endpoint", context do
      Process.link(context.pid)
      TestClient.catch_attr(context.pid, :text, self())
      WebSockex.Client.cast(context.pid, :test_reconnect)

      assert_receive {4985, "Testing Reconnect"}

      server_pid = WebSockex.TestServer.receive_socket_pid
      send(server_pid, {:send, {:text, "Hello"}})

      assert_receive {:caught_text, "Hello"}, 500
    end
  end

  test "Displays an informative error with a bad url" do
    assert TestClient.start_link("lemon_pie", :ok) == {:error, %WebSockex.URLError{url: "lemon_pie"}}
  end

  test "Raises a BadResponseError when a non valid callback response is given", context do
    Process.flag(:trap_exit, true)
    send(context.pid, :bad_reply)
    assert_receive {:EXIT, _, {%WebSockex.BadResponseError{}, _}}
  end
end
