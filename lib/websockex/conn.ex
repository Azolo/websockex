defmodule WebSockex.Conn do
  @moduledoc """
  Handles establishing and controlling the TCP connection.

  Dispatches to the correct module for the underlying connection. (`:gen_tcp` or `:ssl`)

  Is woefully inadequite for verifying proper peers in SSL connections.
  """

  @socket_connect_timeout_default 6000
  @socket_recv_timeout_default 5000

  defstruct conn_mod: nil,
            host: nil,
            port: nil,
            path: nil,
            query: nil,
            extra_headers: [],
            transport: nil,
            socket: nil,
            socket_connect_timeout: @socket_connect_timeout_default,
            socket_recv_timeout: @socket_recv_timeout_default,
            cacerts: nil,
            insecure: true

  @type socket :: :gen_tcp.socket | :ssl.sslsocket
  @type header :: {field :: String.t, value :: String.t}
  @type transport :: :tcp | :ssl

  @type certification :: :public_key.der_encoded

  @typedoc """
  Options used when establishing a tcp or ssl connection.

  - `:extra_headers` - defines other headers to be send in the opening request.
  - `:insecure` - Determines whether to verify the peer in a SSL connection.
    SSL peer verification is currenctly broken and only works in certain cases
    in which the `:cacerts` are also provided. Sorry. _Defaults to `true`_.
  - `:cacerts` - The CA certifications for use in an secure connection when the
    `:insecure` option is `false` (has no effect when `:insecure is true`).
    These certifications need a list of decoded binaries. See the
    [Erlang `:public_key` module][public_key] for more information.
  - `:socket_connect_timeout` - Timeout in ms for creating a connection, default #{@socket_connect_timeout_default} ms.
  - `:socket_recv_timeout` - Timeout in ms for receiving from socket, default #{@socket_recv_timeout_default} ms.

  [public_key]: http://erlang.org/doc/apps/public_key/using_public_key.html
  """
  @type connection_option :: {:extra_headers, [header]} |
                             {:cacerts, [certification]} |
                             {:insecure, boolean} |
                             {:socket_connect_timeout, non_neg_integer}|
                             {:socket_recv_timeout, non_neg_integer}

  @type t :: %__MODULE__{conn_mod: :gen_tcp | :ssl,
                         host: String.t,
                         port: non_neg_integer,
                         path: String.t | nil,
                         query: String.t | nil,
                         extra_headers: [header],
                         transport: transport,
                         socket: socket,
                         socket_connect_timeout: non_neg_integer,
                         socket_recv_timeout: non_neg_integer}

  @doc """
  Returns a new `WebSockex.Conn` struct from a uri and options.
  """
  @spec new(URI.t, [connection_option]) :: __MODULE__.t
  def new(uri, opts \\ []) do
    mod = conn_module(uri.scheme)

    %WebSockex.Conn{host: uri.host,
                    port: uri.port,
                    path: uri.path,
                    query: uri.query,
                    conn_mod: mod,
                    transport: transport(mod),
                    extra_headers: Keyword.get(opts, :extra_headers, []),
                    cacerts: Keyword.get(opts, :cacerts, nil),
                    insecure: Keyword.get(opts, :insecure, true),
                    socket_connect_timeout: Keyword.get(opts, :socket_connect_timeout, @socket_connect_timeout_default),
                    socket_recv_timeout: Keyword.get(opts, :socket_recv_timeout, @socket_recv_timeout_default)}
  end

  @doc """
  Sends data using the `conn_mod` module.
  """
  @spec socket_send(__MODULE__.t, binary) :: :ok | {:error, reason :: term}
  def socket_send(conn, message) do
    case conn.conn_mod.send(conn.socket, message) do
      :ok -> :ok
      {:error, error} -> {:error, %WebSockex.ConnError{original: error}}
    end
  end

  @doc """
  Opens a socket to a uri and returns a conn struct.
  """
  @spec open_socket(__MODULE__.t) :: {:ok, __MODULE__.t} | {:error, term}
  def open_socket(conn)
  def open_socket(%{conn_mod: :gen_tcp} = conn) do
    case :gen_tcp.connect(String.to_charlist(conn.host),
                          conn.port,
                          [:binary, active: false, packet: 0],
                          conn.socket_connect_timeout) do
      {:ok, socket} ->
        {:ok, Map.put(conn, :socket, socket)}
      {:error, error} ->
        {:error, %WebSockex.ConnError{original: error}}
    end
  end
  def open_socket(%{conn_mod: :ssl} = conn) do
    case :ssl.connect(String.to_charlist(conn.host),
                      conn.port,
                      ssl_connection_options(conn),
                      conn.socket_connect_timeout) do
      {:ok, socket} ->
        {:ok, Map.put(conn, :socket, socket)}
      {:error, error} ->
        {:error, %WebSockex.ConnError{original: error}}
    end
  end

  @doc """
  Closes the socket and returns the Conn map without the socket.

  When the `:socket` field is `nil` in the struct, the function just returns
  the struct as is.
  """
  @spec close_socket(__MODULE__.t) :: __MODULE__.t
  def close_socket(conn)
  def close_socket(%{socket: nil} = conn), do: conn
  def close_socket(%{socket: socket} = conn) do
    conn.conn_mod.close(socket)
    %{conn | socket: nil}
  end

  @doc """
  Builds the request to be sent along the newly opened socket.

  The key parameter is part of the websocket handshake process.
  """
  @spec build_request(__MODULE__.t, key :: String.t) :: {:ok, String.t}
  def build_request(conn, key) do
    headers = [{"Host", conn.host},
               {"Connection", "Upgrade"},
               {"Upgrade", "websocket"},
               {"Sec-WebSocket-Version", "13"},
               {"Sec-WebSocket-Key", key}] ++ conn.extra_headers
              |> Enum.map(&format_header/1)

    # Build the request
    request = ["GET #{build_full_path(conn)} HTTP/1.1" | headers]
              |> Enum.join("\r\n")

    {:ok, request <> "\r\n\r\n"}
  end

  @doc """
  Waits for the request response, decodes the packet, and returns the response
  headers.

  Sends any access information in the buffer back to the process as a message
  to be processed.
  """
  @spec handle_response(__MODULE__.t) ::
    {:ok, [header]} | {:error, reason :: term}
  def handle_response(conn) do
    with {:ok, buffer} <- wait_for_response(conn),
         {:ok, headers, buffer} <- decode_response(buffer) do
           # Send excess buffer back to the process
           unless buffer == "" do
             send(self(), {transport(conn.conn_mod), conn.socket, buffer})
           end
           {:ok, headers}
         end
  end

  @doc """
  Sets the socket to active.
  """
  @spec set_active(__MODULE__.t, true | false) :: :ok | {:error, reason :: term}
  def set_active(conn, val \\ true)
  def set_active(%{conn_mod: :gen_tcp} = conn, val) do
    :inet.setopts(conn.socket, active: val)
  end
  def set_active(%{conn_mod: :ssl} = conn, val) do
    :ssl.setopts(conn.socket, active: val)
  end

  defp transport(:gen_tcp), do: :tcp
  defp transport(:ssl), do: :ssl

  defp conn_module("ws"), do: :gen_tcp
  defp conn_module("wss"), do: :ssl

  defp wait_for_response(conn, buffer \\ "") do
    case Regex.match?(~r/\r\n\r\n/, buffer) do
      true -> {:ok, buffer}
      false ->
        with {:ok, data} <- conn.conn_mod.recv(conn.socket, 0, conn.socket_recv_timeout) do
          wait_for_response(conn, buffer <> data)
        else
          {:error, reason} -> {:error, %WebSockex.ConnError{original: reason}}
        end
    end
  end

  defp format_header({field, value}) do
    "#{field}: #{value}"
  end

  defp build_full_path(%__MODULE__{path: path, query: query}) do
    struct(URI, %{path: path, query: query})
    |> URI.to_string
  end

  defp decode_response(response) do
    case :erlang.decode_packet(:http_bin, response, []) do
      {:ok, {:http_response, _version, 101, _message}, rest} ->
         decode_headers(rest)
      {:ok, {:http_response, _, code, message}, _} ->
        {:error, %WebSockex.RequestError{code: code, message: message}}
      {:error, error} ->
        {:error, error}
    end
  end

  defp decode_headers(rest, headers \\ []) do
    case :erlang.decode_packet(:httph_bin, rest, []) do
      {:ok, {:http_header, _len, field, _res, value}, rest} ->
        decode_headers(rest, [{field, value} | headers])
      {:ok, :http_eoh, body} ->
        {:ok, headers, body}
    end
  end

  # Crazy SSL Stuff (It will be normal SSL stuff when I figure out Erlang's ssl)

  defp ssl_connection_options(%{insecure: true}) do
    [
      :binary,
      active: false,
      packet: 0,
      verify: :verify_none
    ]
  end
  defp ssl_connection_options(%{cacerts: cacerts}) when cacerts != nil do
    [
      :binary,
      active: false,
      packet: 0,
      verify: :verify_peer,
      cacerts: cacerts
    ]
  end
end
