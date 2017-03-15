defmodule WebSockex.ConnTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, {server_ref, url}} = WebSockex.TestServer.start(self())

    on_exit fn -> WebSockex.TestServer.shutdown(server_ref) end

    uri = URI.parse(url)
    {:ok, conn} = WebSockex.Conn.open_socket(uri)

    [url: url, uri: uri, conn: conn]
  end

  test "open_socket", context do
    %{host: host, port: port, path: path} = context.uri

    assert {:ok,
      %WebSockex.Conn{host: ^host, port: ^port, path: ^path, socket: _}} =
        WebSockex.Conn.open_socket(context.uri)
  end

  test "open_socket with bad path", context do
    uri = %{context.uri | path: "bad_path"}

    {:ok, conn} = WebSockex.Conn.open_socket(uri)
    {:ok, request} = WebSockex.Conn.build_request(conn, "pants")
    :ok = WebSockex.Conn.socket_send(conn, request)

    assert WebSockex.Conn.handle_response(conn) ==
      {:error, %WebSockex.Conn.RequestError{code: 400, message: "Bad Request"}}
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

    assert request =~ ~r(Get /coco\?nut=true HTTP\/1.1\r\n)
    assert request =~ ~r(Host: #{conn.host}\r\n)
    assert request =~ ~r(Connection: Upgrade\r\n)
    assert request =~ ~r(Sec-WebSocket-Version: 13\r\n)
    assert request =~ ~r(Sec-WebSocket-Key: pants\r\n)
    assert request =~ ~r(Upgrade: websocket\r\n)
    assert request =~ ~r(X-Test: Shoes\r\n)
    assert request =~ ~r(\r\n\r\n\z)
  end
end
