defmodule WebSockex.Conn do
  defstruct conn_mod: :gen_tcp,
            host: nil,
            port: nil,
            path: nil,
            query: nil,
            extra_headers: [],
            transport: :tcp,
            socket: nil

  @type socket :: :gen_tcp.socket
  @type header :: {field :: String.t, value :: String.t}
  @type transport :: :tcp

  @type connection_options :: {:extra_headers, [header]}

  @type t :: %__MODULE__{conn_mod: :gen_tcp,
                         host: String.t,
                         port: non_neg_integer,
                         path: String.t | nil,
                         query: String.t | nil,
                         extra_headers: [header],
                         transport: transport,
                         socket: socket}

  @doc """
  Sends data using the `conn_mod` module.
  """
  @spec socket_send(__MODULE__.t, binary) :: :ok | {:error, reason :: term}
  def socket_send(conn, message) do
    conn.conn_mod.send(conn.socket, message)
  end

  @doc """
  Opens a socket to a uri and returns a conn struct.
  """
  def open_socket(uri, opts \\ []) do
    conn = %__MODULE__{host: uri.host,
                       port: uri.port,
                       path: uri.path,
                       query: uri.query,
                       extra_headers: Keyword.get(opts, :extra_headers, [])}

    case :gen_tcp.connect(String.to_charlist(conn.host),
                          conn.port,
                          [:binary, active: false, packet: 0],
                          6000) do
      {:ok, socket} ->
        {:ok, Map.put(conn, :socket, socket)}
      {:error, error} ->
        {:error, %WebSockex.ConnError{original: error}}
    end
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
    request = ["Get #{build_full_path(conn)} HTTP/1.1" | headers]
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
  @spec set_active(__MODULE__.t) :: :ok | {:error, reason :: term}
  def set_active(%{conn_mod: :gen_tcp} = conn) do
    :inet.setopts(conn.socket, active: true)
  end

  defp transport(:gen_tcp), do: :tcp

  defp wait_for_response(conn, buffer \\ "") do
    case Regex.match?(~r/\r\n\r\n/, buffer) do
      true -> {:ok, buffer}
      false ->
        with {:ok, data} <- conn.conn_mod.recv(conn.socket, 0, 5000) do
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
        {:error, %WebSockex.Conn.RequestError{code: code, message: message}}
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
end
