defmodule WebSockex.Client do
  @handshake_guid "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

  @moduledoc ~S"""
  A client handles negotiating the connection, then sending frames, receiving
  frames, closing, and reconnecting that connection.

  A simple client implementation would be:

  ```
  defmodule WsClient do
    use WebSockex.Client

    def start_link(state) do
      WebSockex.Client.start_link(__MODULE__, state)
    end

    def handle_msg({:text, msg}, state) do
      IO.puts "Received a message: #{msg}"
      {:ok, state}
    end
  end
  ```
  """

  @type message :: {:ping | :ping, nil | binary} | {:text | :binary, binary}
  @type close_message :: {integer, binary}

  @type options :: [option]

  @type option :: {:extra_headers, [WebSockex.Conn.header]}

  @typedoc """
  The reason given and sent to the server when locally closing a connection.

  A `:normal` reason is the same as a `1000` reason.
  """
  @type close_reason :: {:remote | :local, :normal} | {:remote | :local, :normal | integer, close_message} | {:error, term}

  @doc """
  Invoked after connection is established.
  """
  @callback init(args :: any) :: {:ok, state :: term}

  @doc """
  Invoked on the reception of a frame on the socket.

  The control frames have possible payloads, when they don't have a payload
  then the frame will have `nil` as the payload. e.g. `{:ping, nil}`
  """
  @callback handle_msg(message, state :: term) ::
    {:ok, new_state}
    | {:reply, message, new_state}
    | {:close, new_state}
    | {:close, close_message, new_state} when new_state: term

  @doc """
  Invoked to handle asynchronous `cast/2` messages.
  """
  @callback handle_cast(msg :: term, state ::term) ::
    {:ok, new_state}
    | {:reply, message, new_state}
    | {:close, close_message, new_state} when new_state: term

  @doc """
  Invoked to handle all other non-WebSocket messages.
  """
  @callback handle_info(msg :: term, state :: term) ::
    {:ok, new_state}
    | {:reply, message, new_state}
    | {:close, close_message, new_state} when new_state: term

  @doc """
  Invoked when the WebSocket disconnects from the server.
  """
  @callback handle_disconnect(close_reason, state :: term) ::
    {:close, state}
    | {:reconnect, state} when state: term

  @doc """
  Invoked when the Websocket receives a ping frame
  """
  @callback handle_ping(:ping | {:ping, binary}, state :: term) ::
    {:ok, new_state}
    | {:reply, message, new_state}
    | {:close, new_state}
    | {:close, close_message, new_state} when new_state: term

  @doc """
  Invoked when the Websocket receives a pong frame.
  """
  @callback handle_pong(:pong | {:pong, binary}, state :: term) ::
    {:ok, new_state}
    | {:reply, message, new_state}
    | {:close, new_state}
    | {:close, close_message, new_state} when new_state: term

  @doc """
  Invoked when the process is terminating.
  """
  @callback terminate(close_reason, state :: term) :: any

  @doc """
  Invoked when a new version the module is loaded during runtime.
  """
  @callback code_change(old_vsn :: term | {:down, term},
                        state :: term, extra :: term) ::
    {:ok, new_state :: term}
    | {:error, reason :: term}

  @optional_callbacks [handle_disconnect: 2, handle_ping: 2, handle_pong: 2, terminate: 2,
                       code_change: 3]

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour WebSockex.Client

      @doc false
      def init(state) do
        {:ok, state}
      end

      @doc false
      def handle_msg(message, _state) do
        raise "No handle_msg/2 clause provided for #{inspect message}"
      end

      @doc false
      def handle_cast(message, _state) do
        raise "No handle_cast/2 clause provided for #{inspect message}"
      end

      @doc false
      def handle_info(message, state) do
        require Logger
        Logger.error "No handle_info/2 clause provided for #{inspect message}"
        {:ok, state}
      end

      @doc false
      def handle_disconnect(_close_reason, state) do
        {:close, state}
      end

      @doc false
      def handle_ping(:ping, state) do
        {:reply, :pong, state}
      end
      def handle_ping({:ping, msg}, state) do
        {:reply, {:pong, msg}, state}
      end

      @doc false
      def handle_pong(:pong, state), do: {:ok, state}
      def handle_pong({:pong, _}, state), do: {:ok, state}

      @doc false
      def terminate(_close_reason, _state), do: :ok

      @doc false
      def code_change(_old_vsn, state, _extra), do: {:ok, state}

      defoverridable [init: 1, handle_msg: 2, handle_cast: 2, handle_info: 2, handle_ping: 2,
                      handle_pong: 2, handle_disconnect: 2, terminate: 2, code_change: 3]
    end
  end

  def start_link(url, module, state, opts \\ []) do
    case URI.parse(url) do
      # This is confusing to look at. But it's just a match with multiple guards
      %URI{host: host, port: port, scheme: protocol}
      when is_nil(host)
      when is_nil(port)
      when not protocol in ["ws", "wss"] ->
        {:error, %WebSockex.URLError{url: url}}
      %URI{} = uri ->
        :proc_lib.start_link(__MODULE__, :init, [self(), uri, module, state, opts])
      {:error, error} ->
        {:error, error}
    end
  end

  def cast(socket, message) do
    send(socket, {:"$websockex_cast", message})
    :ok
  end

  def init(parent, uri, module, state, opts) do
    # OTP stuffs
    debug = :sys.debug_options([])

    try do
    with {:ok, conn} <- WebSockex.Conn.open_socket(uri, opts),
         key <- :crypto.strong_rand_bytes(16) |> Base.encode64,
         {:ok, request} <- WebSockex.Conn.build_request(conn, key),
         :ok <- WebSockex.Conn.socket_send(conn, request),
         {:ok, headers} <- WebSockex.Conn.handle_response(conn),
         :ok <- validate_handshake(headers, key),
         :ok <- WebSockex.Conn.set_active(conn) do
           :proc_lib.init_ack(parent, {:ok, self()})
           websocket_loop(parent, debug, %{conn: conn, module: module, module_state: state})
         else
           {:error, reason} ->
             error = Exception.normalize(:error, reason)
             :proc_lib.init_ack(parent, error)
             exit(error)
         end
    rescue
      exception ->
        exit({exception, System.stacktrace})
    end
  end

  ## OTP Stuffs

  def system_continue(parent, debug, state) do
    websocket_loop(parent, debug, state)
  end

  def system_terminate(reason, parent, debug, state) do
    terminate(reason, parent, debug, state)
  end

  def system_get_state(state) do
    {:ok, state, state}
  end

  def system_replace_state(fun, state) do
    new_state = fun.(state)
    {:ok, new_state, new_state}
  end

  # Internals! Yay

  defp validate_handshake(headers, key) do
    challenge = :crypto.hash(:sha, key <> @handshake_guid) |> Base.encode64

    {_, res} = List.keyfind(headers, "Sec-Websocket-Accept", 0)

    if challenge == res do
      :ok
    else
      {:error, %WebSockex.HandshakeError{response: res, challenge: challenge}}
    end
  end

  defp websocket_loop(parent, debug, state) do
    transport = state.conn.transport
    socket = state.conn.socket
    receive do
      {:system, from, req} ->
        :sys.handle_system_msg(req, from, parent, __MODULE__, debug, state)
      {:"$websockex_cast", msg} ->
        common_handle({:handle_cast, msg}, parent, debug, state)
      {^transport, ^socket, message} ->
        with {:ok, frame, _} <- WebSockex.Frame.parse_frame(message) do
          handle_frame(frame, parent, debug, state)
        end
      msg ->
        common_handle({:handle_info, msg}, parent, debug, state)
    end
  end

  defp common_handle({function, msg}, parent, debug, state) do
    case apply(state.module, function, [msg, state.module_state]) do
      {:ok, new_state} ->
        websocket_loop(parent, debug, %{state | module_state: new_state})
      {:reply, frame, new_state} ->
        with {:ok, binary_frame} <- WebSockex.Frame.encode_frame(frame),
             :ok <- WebSockex.Conn.socket_send(state.conn, binary_frame) do
          websocket_loop(parent, debug, %{state | module_state: new_state})
        else
          {:error, error} ->
            raise error
        end
      {:close, new_state} ->
        with {:ok, binary_frame} <- WebSockex.Frame.encode_frame(:close),
             :ok <- WebSockex.Conn.socket_send(state.conn, binary_frame) do
          terminate({:local, :normal}, parent, debug, %{state | module_state: new_state})
        else
          {:error, error} ->
            raise error
        end
      {:close, {close_code, message}, new_state} ->
        with {:ok, binary_frame} <- WebSockex.Frame.encode_frame({:close, close_code, message}),
             :ok <- WebSockex.Conn.socket_send(state.conn, binary_frame) do
          terminate({:local, close_code, message}, parent, debug, %{state | module_state: new_state})
        else
          {:error, error} ->
            raise error
        end
      badreply ->
        raise %WebSockex.BadResponseError{module: state.module,
          function: function, args: [msg, state.module_state],
          response: badreply}
    end
  rescue
    exception ->
      terminate({exception, System.stacktrace}, parent, debug, state)
  end

  defp handle_frame(:ping, parent, debug, state) do
    common_handle({:handle_ping, :ping}, parent, debug, state)
  end
  defp handle_frame({:ping, msg}, parent, debug, state) do
    common_handle({:handle_ping, {:ping, msg}}, parent, debug, state)
  end
  defp handle_frame(:pong, parent, debug, state) do
    common_handle({:handle_pong, :pong}, parent, debug, state)
  end
  defp handle_frame({:pong, msg}, parent, debug, state) do
    common_handle({:handle_pong, {:pong, msg}}, parent, debug, state)
  end

  defp terminate(reason, _parent, _debug, %{module: mod, module_state: mod_state}) do
    mod.terminate(reason, mod_state)
    case reason do
      {_, :normal} ->
        exit(:normal)
      {_, 1000, _} ->
        exit(:normal)
      _ ->
        exit(reason)
    end
  end
end
