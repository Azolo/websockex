defmodule WebSockex.ConnTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, {server_ref, url}} = WebSockex.TestServer.start(self())

    on_exit fn -> WebSockex.TestServer.shutdown(server_ref) end

    uri = URI.parse(url)

    conn = WebSockex.Conn.new(uri)

    {:ok, conn} = WebSockex.Conn.open_socket(conn)

    [url: url, uri: uri, conn: conn]
  end

  test "new" do
    regular_uri = URI.parse("ws://localhost/ws")
    assert WebSockex.Conn.new(regular_uri,
                              extra_headers: [{"Pineapple", "Cake"}],
                              socket_connect_timeout: 123,
                              socket_recv_timeout: 456) ==
      %WebSockex.Conn{host: "localhost",
                      port: 80,
                      path: "/ws",
                      query: nil,
                      conn_mod: :gen_tcp,
                      transport: :tcp,
                      extra_headers: [{"Pineapple", "Cake"}],
                      socket: nil,
                      socket_connect_timeout: 123,
                      socket_recv_timeout: 456}

    ssl_uri = URI.parse("wss://localhost/ws")
    assert WebSockex.Conn.new(ssl_uri, extra_headers: [{"Pineapple", "Cake"}]) ==
      %WebSockex.Conn{host: "localhost",
                      port: 443,
                      path: "/ws",
                      query: nil,
                      conn_mod: :ssl,
                      transport: :ssl,
                      extra_headers: [{"Pineapple", "Cake"}],
                      socket: nil,
                      socket_connect_timeout: 6000,
                      socket_recv_timeout: 5000}

    http_uri = URI.parse("http://localhost/ws")
    assert WebSockex.Conn.new(http_uri,
                              extra_headers: [{"Pineapple", "Cake"}]) ==
      %WebSockex.Conn{host: "localhost",
                      port: 80,
                      path: "/ws",
                      query: nil,
                      conn_mod: :gen_tcp,
                      transport: :tcp,
                      extra_headers: [{"Pineapple", "Cake"}],
                      socket: nil}

    https_uri = URI.parse("https://localhost/ws")
    assert WebSockex.Conn.new(https_uri, extra_headers: [{"Pineapple", "Cake"}]) ==
      %WebSockex.Conn{host: "localhost",
                      port: 443,
                      path: "/ws",
                      query: nil,
                      conn_mod: :ssl,
                      transport: :ssl,
                      extra_headers: [{"Pineapple", "Cake"}],
                      socket: nil,
                      socket_connect_timeout: 6000,
                      socket_recv_timeout: 5000}

    llama = URI.parse("llama://localhost/ws")
    assert WebSockex.Conn.new(llama, extra_headers: [{"Pineapple", "Cake"}]) == %WebSockex.Conn{host: "localhost",
                      port: nil,
                      path: "/ws",
                      query: nil,
                      conn_mod: nil,
                      transport: nil,
                      extra_headers: [{"Pineapple", "Cake"}],
                      socket: nil,
                      socket_connect_timeout: 6000,
                      socket_recv_timeout: 5000}
  end

  test "open_socket", context do
    %{host: host, port: port, path: path} = context.uri

    assert {:ok,
      %WebSockex.Conn{host: ^host, port: ^port, path: ^path, socket: _}} =
        WebSockex.Conn.open_socket(context.conn)
  end

  test "open_socket with bad path", context do
    conn = %{context.conn | path: "bad_path"}

    {:ok, conn} = WebSockex.Conn.open_socket(conn)
    {:ok, request} = WebSockex.Conn.build_request(conn, "pants")
    :ok = WebSockex.Conn.socket_send(conn, request)

    assert WebSockex.Conn.handle_response(conn) ==
      {:error, %WebSockex.RequestError{code: 400, message: "Bad Request"}}
  end

  describe "secure connection" do
    setup do
      {:ok, {server_ref, url}} = WebSockex.TestServer.start_https(self())

      on_exit fn -> WebSockex.TestServer.shutdown(server_ref) end

      uri = URI.parse(url)

      {:ok, conn} = WebSockex.Conn.new(uri) |> WebSockex.Conn.open_socket

      [url: url, uri: uri, conn: conn]
    end

    test "open_socket with supplied cacerts", context do
      conn = WebSockex.Conn.new(context.uri, [insecure: false,
                                              cacerts: WebSockex.TestServer.cacerts()])

      assert {:ok, %WebSockex.Conn{conn_mod: :ssl, transport: :ssl, insecure: false}} =
        WebSockex.Conn.open_socket(conn)
    end

    test "open_socket with insecure flag", context do
      conn = WebSockex.Conn.new(context.uri, insecure: true)

      assert {:ok, %WebSockex.Conn{conn_mod: :ssl, transport: :ssl, insecure: true}} =
        WebSockex.Conn.open_socket(conn)
    end

    test "close_socket", context do
      socket = context.conn.socket

      assert {:ok, _} = :ssl.sockname(socket)
      assert WebSockex.Conn.close_socket(context.conn) == %{context.conn | socket: nil}
      Process.sleep 50
      assert {:error, _} = :ssl.sockname(socket)
    end
  end

  test "close_socket", context do
    socket = context.conn.socket

    assert {:ok, _} = :inet.port(socket)
    assert WebSockex.Conn.close_socket(context.conn) == %{context.conn | socket: nil}
    assert :inet.port(socket) == {:error, :einval}
  end

  test "close_socket with nil socket", context do
    conn = %{context.conn | socket: nil}
    assert conn.socket == nil

    assert WebSockex.Conn.close_socket(conn) == conn
  end

  describe "set_active" do
    test "works on ws connections", context do
      assert :inet.getopts(context.conn.socket, [:active]) == {:ok, active: false}
      assert WebSockex.Conn.set_active(context.conn, true) == :ok
      assert :inet.getopts(context.conn.socket, [:active]) == {:ok, active: true}
      assert WebSockex.Conn.set_active(context.conn, false) == :ok
      assert :inet.getopts(context.conn.socket, [:active]) == {:ok, active: false}
    end

    test "works on wss connections" do
      {:ok, {server_ref, url}} = WebSockex.TestServer.start_https(self())
      on_exit fn -> WebSockex.TestServer.shutdown(server_ref) end
      uri = URI.parse(url)
      conn = WebSockex.Conn.new(uri)
      {:ok, conn} = WebSockex.Conn.open_socket(conn)

      assert :ssl.getopts(conn.socket, [:active]) == {:ok, active: false}
      assert WebSockex.Conn.set_active(conn, true) == :ok
      assert :ssl.getopts(conn.socket, [:active]) == {:ok, active: true}
      assert WebSockex.Conn.set_active(conn, false) == :ok
      assert :ssl.getopts(conn.socket, [:active]) == {:ok, active: false}
    end

    test "sets to true by default", context do
      assert :inet.getopts(context.conn.socket, [:active]) == {:ok, active: false}
      assert WebSockex.Conn.set_active(context.conn) == :ok
      assert :inet.getopts(context.conn.socket, [:active]) == {:ok, active: true}
    end
  end

  test "socket_send returns a send error when fails to send", %{conn: conn} do
    socket = conn.socket
    :ok = conn.conn_mod.close(socket)
    assert WebSockex.Conn.socket_send(conn, "Gonna Fail") ==
      {:error, %WebSockex.ConnError{original: :closed}}
  end

  test "build_request" do
    conn = %WebSockex.Conn{host: "lime.com",
                           path: "/coco",
                           query: "nut=true",
                           extra_headers: [{"X-Test", "Shoes"}]}

    {:ok, request} = WebSockex.Conn.build_request(conn, "pants")

    assert request =~ ~r(GET /coco\?nut=true HTTP\/1.1\r\n)
    assert request =~ ~r(Host: #{conn.host}\r\n)
    assert request =~ ~r(Connection: Upgrade\r\n)
    assert request =~ ~r(Sec-WebSocket-Version: 13\r\n)
    assert request =~ ~r(Sec-WebSocket-Key: pants\r\n)
    assert request =~ ~r(Upgrade: websocket\r\n)
    assert request =~ ~r(X-Test: Shoes\r\n)
    assert request =~ ~r(\r\n\r\n\z)
  end

  test "controlling_process", %{conn: conn} do
    socket = conn.socket
    # Start a random process
    {:ok, agent_pid} = Agent.start_link(fn -> :test end)

    assert :erlang.port_info(socket, :connected) == {:connected, self()}

    WebSockex.Conn.controlling_process(conn, agent_pid)

    assert :erlang.port_info(socket, :connected) == {:connected, agent_pid}
  end
end
