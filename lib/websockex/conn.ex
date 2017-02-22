defmodule WebSockex.Conn do
  @handshake_guid "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

  defstruct conn_mod: :gen_tcp,
            host: nil,
            port: nil,
            request: nil,
            socket: nil

  @type socket :: :gen_tcp.socket
  @type t :: %__MODULE__{conn_mod: :gen_tcp,
                         host: String.t,
                         port: non_neg_integer,
                         request: String.t,
                         socket: socket}
            
  @spec connect(URI.t) :: {:ok, __MODULE__.t}
  def connect(uri) do
    conn = %__MODULE__{host: uri.host,
                       port: uri.port,
                       request: build_full_path(uri)}

    with {:ok, socket} <- open_socket(conn),
         conn <- Map.put(conn, :socket, socket),
         {handshake, key} <- build_handshake(conn),
         :ok <- conn.conn_mod.send(socket, handshake),
         {:ok, response} <- wait_for_response(conn),
         {:ok, headers, rest} <- decode_response(response),
         :ok <- validate_handshake(headers, key) do
           unless "" == rest, do: send(self(), {:tcp, conn.socket, rest})

           :inet.setopts(conn.socket, active: true)
           {:ok, conn}
         else
           {:error, _} = error ->
             :proc_lib.init_ack(error)
             exit(error)
         end
  end

  defp open_socket(conn) do
    :gen_tcp.connect(String.to_charlist(conn.host),
                     conn.port,
                     [:binary, active: false, packet: 0],
                     6000)
  end

  defp decode_response(response) do
    case :erlang.decode_packet(:http_bin, response, []) do 
      {:ok, {:http_response, _version, 101, _message}, rest} ->
         decode_headers(rest)
      {:ok, {:http_response, _, code, message}, _} ->
        {:error, {code, message}}
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

  defp validate_handshake(headers, key) do
    challenge = :crypto.hash(:sha, key <> @handshake_guid) |> Base.encode64

    {_, res} = List.keyfind(headers, "Sec-Websocket-Accept", 0)

    if challenge == res do
      :ok
    else
      {:error, :invalid_challenge_response}
    end
  end

  defp wait_for_response(conn, buffer \\ "") do
    case Regex.match?(~r/\r\n\r\n/, buffer) do
      true -> {:ok, buffer}
      false ->
        with {:ok, data} <- conn.conn_mod.recv(conn.socket, 0) do
          wait_for_response(conn, buffer <> data)
        else
          _ -> raise buffer
        end
    end
  end

  defp build_handshake(conn) do
    key = :crypto.strong_rand_bytes(16) |> Base.encode64

    request = ["Get #{conn.request} HTTP/1.1",
               "Host: #{conn.host}",
               "Connection: Upgrade",
               "Sec-WebSocket-Version: 13",
               "Sec-WebSocket-Key: #{key}",
               "Upgrade: websocket",
               "\r\n"]
              |> Enum.join("\r\n")

    {request, key}
  end

  defp build_full_path(%URI{path: path, query: query}) do
    struct(URI, %{path: path, query: query})
    |> URI.to_string
  end
end
