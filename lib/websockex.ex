defmodule WebSockex do
  @handshake_guid "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

  @moduledoc ~S"""
  A client handles negotiating the connection, then sending frames, receiving
  frames, closing, and reconnecting that connection.

  A simple client implementation would be:

  ```
  defmodule WsClient do
    use WebSockex

    def start_link(url, state) do
      WebSockex.start_link(url, __MODULE__, state)
    end

    def handle_frame({:text, msg}, state) do
      IO.puts "Received a message: #{msg}"
      {:ok, state}
    end
  end
  ```
  """

  @type frame :: {:ping | :ping, nil | message :: binary}
                 | {:text | :binary, message :: binary}

  @typedoc """
  The frame sent when the negotiating a connection closure.
  """
  @type close_frame :: {close_code, message :: binary}

  @typedoc """
  An integer between 1000 and 4999 that specifies the reason for closing the connection.
  """
  @type close_code :: integer

  @type options :: [option]

  @typedoc """
  Options values for `start_link`.

  - `:async` - Replies with `{:ok, pid}` before establishing the connection.
    This is useful for when attempting to connect indefinitely, this way the
    process doesn't block trying to establish a connection.
  - `:handle_initial_conn_failure` - When set to `true` a connection failure
    while establishing the initial connection won't immediately return an error
    and instead will invoke the `c:handle_disconnect/2` callback. This option
    only matters during process initialization. The `handle_disconnect`
    callback is always invoked if an established connection is lost.

  Other possible option values include: `t:WebSockex.Conn.connection_option/0`
  """
  @type option :: WebSockex.Conn.connection_option
                  | {:async, boolean}
                  | {:handle_initial_conn_failure, boolean}

  @typedoc """
  The reason a connection was closed.

  A `:normal` reason is the same as a `1000` reason with no payload.

  If the peer closes the connection abruptly without a close frame then the
  close reason is `{:remote, :closed}`.
  """
  @type close_reason :: {:remote | :local, :normal}
                        | {:remote | :local, close_code, message :: binary}
                        | {:remote, :closed}
                        | {:error, term}

  @typedoc """
  The error returned when a connection fails to be established.
  """
  @type close_error :: %WebSockex.RequestError{}
                       | %WebSockex.ConnError{}
                       | %WebSockex.InvalidFrameError{}
                       | %WebSockex.FrameEncodeError{}

  @typedoc """
  A map that contains information about the failure to connect.

  This map contains the error, attempt number, and the `t:WebSockex.Conn.t/0`
  that was used to attempt the connection.
  """
  @type connection_status_map :: %{reason: close_reason | close_error,
                                   attempt_number: integer,
                                   conn: WebSockex.Conn.t}

  @doc """
  Invoked after a connection is established.

  This is invoked after both the initial connection and a reconnect.
  """
  @callback handle_connect(conn :: WebSockex.Conn.t, state :: term) ::
    {:ok, new_state :: term}

  @doc """
  Invoked on the reception of a frame on the socket.

  The control frames have possible payloads, when they don't have a payload
  then the frame will have `nil` as the payload. e.g. `{:ping, nil}`
  """
  @callback handle_frame(frame, state :: term) ::
    {:ok, new_state}
    | {:reply, frame, new_state}
    | {:close, new_state}
    | {:close, close_frame, new_state} when new_state: term

  @doc """
  Invoked to handle asynchronous `cast/2` messages.
  """
  @callback handle_cast(msg :: term, state :: term) ::
    {:ok, new_state}
    | {:reply, frame, new_state}
    | {:close, new_state}
    | {:close, close_frame, new_state} when new_state: term

  @doc """
  Invoked to handle all other non-WebSocket messages.
  """
  @callback handle_info(msg :: term, state :: term) ::
    {:ok, new_state}
    | {:reply, frame, new_state}
    | {:close, new_state}
    | {:close, close_frame, new_state} when new_state: term

  @doc """
  Invoked when the WebSocket disconnects from the server.

  This callback is only invoked in the even of a connection failure. In cases
  of crashes or other errors then the process will terminate immediately
  skipping this callback.

  If the `handle_initial_conn_failure: true` option is provided during process
  startup, then this callback will be invoked if the process fails to establish
  an initial connection.

  If a connection is established by reconnecting, the `c:handle_connect/2`
  callback will be invoked.

  The possible returns for this callback are:

  - `{:ok, state}` will continue the process termination.
  - `{:reconnect, state}` will attempt to reconnect instead of terminating.
  - `{:reconnect, conn, state}` will attempt to reconnect with the connection
    data in `conn`. `conn` is expected to be a `t:WebSockex.Conn.t/0`.
  """
  @callback handle_disconnect(connection_status_map, state :: term) ::
    {:ok, new_state}
    | {:reconnect, new_state}
    | {:reconnect, new_conn :: WebSockex.Conn.t, new_state} when new_state: term

  @doc """
  Invoked when the Websocket receives a ping frame
  """
  @callback handle_ping(ping_frame :: :ping | {:ping, binary}, state :: term) ::
    {:ok, new_state}
    | {:reply, frame, new_state}
    | {:close, new_state}
    | {:close, close_frame, new_state} when new_state: term

  @doc """
  Invoked when the Websocket receives a pong frame.
  """
  @callback handle_pong(pong_frame :: :pong | {:pong, binary}, state :: term) ::
    {:ok, new_state}
    | {:reply, frame, new_state}
    | {:close, new_state}
    | {:close, close_frame, new_state} when new_state: term

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

  @doc """
  Invoked to to retrieve a formatted status of the state in a WebSockex process.

  This optional callback is used when you want to edit the values returned when
  invoking `:sys.get_status`.

  The second argument is a two-element list with the order of `[pdict, state]`.
  """
  @callback format_status(:normal, [process_dictionary | state]) :: status :: term
  when process_dictionary: [{key :: term, val :: term}], state: term

  @optional_callbacks format_status: 2

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour WebSockex

      @doc false
      def handle_connect(_conn, state) do
        {:ok, state}
      end

      @doc false
      def handle_frame(frame, _state) do
        raise "No handle_frame/2 clause in #{__MODULE__} provided for #{inspect frame}"
      end

      @doc false
      def handle_cast(message, _state) do
        raise "No handle_cast/2 clause in #{__MODULE__} provided for #{inspect message}"
      end

      @doc false
      def handle_info(message, state) do
        require Logger
        Logger.error "No handle_info/2 clause in #{__MODULE__} provided for #{inspect message}"
        {:ok, state}
      end

      @doc false
      def handle_disconnect(_connection_status_map, state) do
        {:ok, state}
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

      defoverridable [handle_connect: 2, handle_frame: 2, handle_cast: 2, handle_info: 2, handle_ping: 2,
                      handle_pong: 2, handle_disconnect: 2, terminate: 2, code_change: 3]
    end
  end

  @doc """
  Starts a `WebSockex` process.

  Acts like `start_link/4`, except doesn't link the current process.

  See `start_link/4` for more information.
  """
  @spec start(url :: String.t | WebSockex.Conn.t, module, term, options) ::
    {:ok, pid} | {:error, term}
  def start(conn_info, module, state, opts \\ [])
  def start(%WebSockex.Conn{} = conn, module, state, opts) do
    :proc_lib.start(__MODULE__, :init, [self(), conn, module, state, opts])
  end
  def start(url, module, state, opts) do
    case parse_uri(url) do
      {:ok, uri} ->
        conn = WebSockex.Conn.new(uri, opts)
        start(conn, module, state, opts)
      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Starts a `WebSockex` process linked to the current process.

  For available option values see `t:option/0`.

  If a `WebSockex.Conn.t` is used in place of a url string, then the options
  available in `t:WebSockex.Conn.connection_option/0` have effect.

  The callback `c:handle_connect/2` is invoked after the connection is
  established.
  """
  @spec start_link(url :: String.t | WebSockex.Conn.t, module, term, options) ::
    {:ok, pid} | {:error, term}
  def start_link(conn_info, module, state, opts \\ [])
  def start_link(conn = %WebSockex.Conn{}, module, state, opts) do
    :proc_lib.start_link(__MODULE__, :init, [self(), conn, module, state, opts])
  end
  def start_link(url, module, state, opts) do
    case parse_uri(url) do
      {:ok, uri} ->
        conn = WebSockex.Conn.new(uri, opts)
        start_link(conn, module, state, opts)
      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Asynchronously sends a message to a client that is handled by `c:handle_cast/2`.
  """
  @spec cast(pid, term) :: :ok
  def cast(client, message) do
    send(client, {:"$websockex_cast", message})
    :ok
  end

  @doc """
  Queue a frame to be sent asynchronously.
  """
  @spec send_frame(pid, frame) :: :ok | {:error, %WebSockex.FrameEncodeError{}
                                                 | %WebSockex.ConnError{}
                                                 | %WebSockex.InvalidFrameError{}}
  def send_frame(pid, frame) do
    try do
      {:ok, res} = :gen.call(pid, :"$websockex_send", frame)
      res
    catch
      _, reason ->
        exit({reason, {__MODULE__, :call, [pid, frame]}})
    end
  end

  @doc false
  @spec init(pid, WebSockex.Conn.t, module, term, options) ::
    {:ok, pid} | {:error, term}
  def init(parent, conn, module, module_state, opts) do
    # OTP stuffs
    debug = :sys.debug_options([])

    reply_fun = case Keyword.get(opts, :async, false) do
                  true ->
                    :proc_lib.init_ack(parent, {:ok, self()})
                    &async_init_fun/1
                  false ->
                    &sync_init_fun(parent, &1)
                end

    state = %{conn: conn,
              module: module,
              module_state: module_state,
              reply_fun: reply_fun,
              buffer: <<>>,
              fragment: nil}

    handle_conn_failure = Keyword.get(opts, :handle_initial_conn_failure, false)

    case open_connection(parent, debug, state) do
      {:ok, new_state} ->
        module_init(parent, debug, new_state)
      {:error, error, new_state} when handle_conn_failure == true ->
        init_conn_failure(error, parent, debug, new_state)
      {:error, error, _} ->
        state.reply_fun.({:error, error})
    end
  end

  ## OTP Stuffs

  @doc false
  def system_continue(parent, debug, %{connection_status: :connected} = state) do
    websocket_loop(parent, debug, Map.delete(state, :connection_status))
  end
  def system_continue(parent, debug, %{connection_status: :connecting} = state) do
    open_loop(parent, debug, Map.delete(state, :connection_status))
  end
  def system_continue(parent, debug, %{connection_status: {:closing, reason}} = state) do
    close_loop(reason, parent, debug, Map.delete(state, :connection_status))
  end

  @doc false
  @spec system_terminate(term, pid, any, any) :: no_return
  def system_terminate(reason, parent, debug, state) do
    terminate(reason, parent, debug, state)
  end

  @doc false
  def system_get_state(%{module_state: module_state}) do
    {:ok, module_state}
  end

  @doc false
  def system_replace_state(fun, state) do
    new_module_state = fun.(state.module_state)
    {:ok, new_module_state, %{state | module_state: new_module_state}}
  end

  @doc false
  def system_code_change(state, _mod, old_vsn, extra) do
    case apply(state.module, :code_change, [old_vsn, state.module_state, extra]) do
      {:ok, new_module_state} ->
        {:ok, %{state | module_state: new_module_state}}
      other -> other
    end
  catch
    other -> other
  end

  @doc false
  def format_status(opt, [pdict, sys_state, parent, debug, state]) do
    log = :sys.get_debug(:log, debug, [])
    module_misc = module_status(opt, state.module, pdict, state.module_state)

    [{:header, 'Status for WebSockex process #{inspect self()}'},
     {:data, [{"Status", sys_state},
            {"Parent", parent},
            {"Log", log},
            {"Connection Status", state.connection_status},
            {"Socket Buffer", state.buffer},
            {"Socket Module", state.module}]} | module_misc]
  end

  defp module_status(opt, module, pdict, module_state) do
    default = [{:data, [{"State", module_state}]}]

    if function_exported?(module, :format_status, 2) do
      result = try_callback(module, :format_status, [opt, [pdict, module_state]])

      case result do
        {:"$EXIT", _} ->
          require Logger
          Logger.error "There was an error while invoking #{module}.format_status/2"
          default
        other when is_list(other) -> other
        other -> [other]
      end
    else
      default
    end
  end

  # Internals! Yay

  # Loops

  defp open_loop(parent, debug, state) do
    %{task: %{ref: ref}} = state
    receive do
      {:system, from, req} ->
        state = Map.put(state, :connection_status, :connecting)
        :sys.handle_system_msg(req, from, parent, __MODULE__, debug, state)
      {:EXIT, ^parent, reason} ->
        case state do
          %{reply_fun: reply_fun} ->
            reply_fun.(reason)
            exit(reason)
          _ ->
            terminate(reason, parent, debug, state)
        end
      {^ref, {:ok, new_conn}} ->
        Process.demonitor(ref, [:flush])
        new_state = Map.delete(state, :task)
                    |> Map.put(:conn, new_conn)
        {:ok, new_state}
      {^ref, {:error, reason}} ->
        Process.demonitor(ref, [:flush])
        new_state = Map.delete(state, :task)
        {:error, reason, new_state}
    end
  end

  defp websocket_loop(parent, debug, state) do
    case WebSockex.Frame.parse_frame(state.buffer) do
      {:ok, frame, buffer} ->
        handle_frame(frame, parent, debug, %{state | buffer: buffer})
      :incomplete ->
        transport = state.conn.transport
        socket = state.conn.socket
        receive do
          {:system, from, req} ->
            state = Map.put(state, :connection_status, :connected)
            :sys.handle_system_msg(req, from, parent, __MODULE__, debug, state)
          {:"$websockex_cast", msg} ->
            common_handle({:handle_cast, msg}, parent, debug, state)
          {:"$websockex_send", from, frame} ->
            sync_send(frame, from, parent, debug, state)
          {^transport, ^socket, message} ->
            buffer = <<state.buffer::bitstring, message::bitstring>>
            websocket_loop(parent, debug, %{state | buffer: buffer})
          {:tcp_closed, ^socket} ->
            handle_close({:remote, :closed}, parent, debug, state)
          :"websockex_close_timeout" ->
            websocket_loop(parent, debug, state)
          {:EXIT, ^parent, reason} ->
            terminate(reason, parent, debug, state)
          msg ->
            common_handle({:handle_info, msg}, parent, debug, state)
        end
    end
  end

  defp close_loop(reason, parent, debug, %{conn: conn} = state) do
    transport = state.conn.transport
    socket = state.conn.socket
    receive do
      {:system, from, req} ->
        state = Map.put(state, :connection_status, {:closing, reason})
        :sys.handle_system_msg(req, from, parent, __MODULE__, debug, state)
      {:EXIT, ^parent, reason} ->
        terminate(reason, parent, debug, state)
      {^transport, ^socket, _} ->
        close_loop(reason, parent, debug, state)
      {:tcp_closed, ^socket} ->
        new_conn = %{conn | socket: nil}
        on_disconnect(reason, parent, debug, %{state | conn: new_conn})
      :"$websockex_close_timeout" ->
        new_conn = WebSockex.Conn.close_socket(conn)
        on_disconnect(reason, parent, debug, %{state | conn: new_conn})
    end
  end

  # Frame Handling

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
  defp handle_frame(:close, parent, debug, state) do
    handle_close({:remote, :normal}, parent, debug, state)
  end
  defp handle_frame({:close, code, reason}, parent, debug, state) do
    handle_close({:remote, code, reason}, parent, debug, state)
  end
  defp handle_frame({:fragment, _, _} = fragment, parent, debug, state) do
    handle_fragment(fragment, parent, debug, state)
  end
  defp handle_frame({:continuation, _} = fragment, parent, debug, state) do
    handle_fragment(fragment, parent, debug, state)
  end
  defp handle_frame({:finish, _} = fragment, parent, debug, state) do
    handle_fragment(fragment, parent, debug, state)
  end
  defp handle_frame(frame, parent, debug, state) do
    common_handle({:handle_frame, frame}, parent, debug, state)
  end

  defp handle_fragment({:fragment, type, part}, parent, debug, %{fragment: nil} = state) do
    websocket_loop(parent, debug, %{state | fragment: {type, part}})
  end
  defp handle_fragment({:fragment, _, _}, parent, debug, state) do
    handle_close({:local, 1002, "Endpoint tried to start a fragment without finishing another"}, parent, debug, state)
  end
  defp handle_fragment({:continuation, _}, parent, debug, %{fragment: nil} = state) do
    handle_close({:local, 1002, "Endpoint sent a continuation frame without starting a fragment"}, parent, debug, state)
  end
  defp handle_fragment({:continuation, next}, parent, debug, %{fragment: {type, part}} = state) do
    websocket_loop(parent, debug, %{state | fragment: {type, <<part::binary, next::binary>>}})
  end
  defp handle_fragment({:finish, next}, parent, debug, %{fragment: {type, part}} = state) do
    handle_frame({type, <<part::binary, next::binary>>}, parent, debug, %{state | fragment: nil})
  end

  defp handle_close({:remote, :closed} = reason, parent, debug, state) do
    new_conn = %{state.conn | socket: nil}
    on_disconnect(reason, parent, debug, %{state | conn: new_conn})
  end
  defp handle_close({:remote, _} = reason, parent, debug, state) do
    handle_remote_close(reason, parent, debug, state)
  end
  defp handle_close({:remote, _, _} = reason, parent, debug, state) do
    handle_remote_close(reason, parent, debug, state)
  end
  defp handle_close({:local, _} = reason, parent, debug, state) do
    handle_local_close(reason, parent, debug, state)
  end
  defp handle_close({:local, _, _} = reason, parent, debug, state) do
    handle_local_close(reason, parent, debug, state)
  end
  defp handle_close({:error, _} = reason, parent, debug, state) do
    handle_error_close(reason, parent, debug, state)
  end

  defp common_handle({function, msg}, parent, debug, state) do
    result = try_callback(state.module, function, [msg, state.module_state])

    case result do
      {:ok, new_state} ->
        websocket_loop(parent, debug, %{state | module_state: new_state})
      {:reply, frame, new_state} ->
        # A `with` that includes `else` clause isn't tail recursive (elixir-lang/elixir#6251)
        res = with {:ok, binary_frame} <- WebSockex.Frame.encode_frame(frame),
              do: :ok = WebSockex.Conn.socket_send(state.conn, binary_frame)
        case res do
          :ok -> websocket_loop(parent, debug, %{state | module_state: new_state})
          {:error, error} ->
            handle_close({:error, error}, parent, debug, %{state | module_state: new_state})
        end
      {:close, new_state} ->
        handle_close({:local, :normal}, parent, debug, %{state | module_state: new_state})
      {:close, {close_code, message}, new_state} ->
        handle_close({:local, close_code, message}, parent, debug, %{state | module_state: new_state})
      {:"$EXIT", reason} ->
        handle_error_close(reason, parent, debug, state)
      badreply ->
        error = %WebSockex.BadResponseError{module: state.module, function: function,
          args: [msg, state.module_state], response: badreply}
        terminate(error, parent, debug, state)
    end
  end

  defp handle_remote_close(reason, parent, debug, state) do
    # If the socket is already closed then that's ok, but the spec says to send
    # the close frame back in response to receiving it.
    send_close_frame(reason, state.conn)

    Process.send_after(self(), :"$websockex_close_timeout", 5000)
    close_loop(reason, parent, debug, state)
  end

  defp handle_local_close(reason, parent, debug, state) do
    case send_close_frame(reason, state.conn) do
      :ok ->
        Process.send_after(self(), :"$websockex_close_timeout", 5000)
        close_loop(reason, parent, debug, state)
      {:error, %WebSockex.ConnError{original: :closed}} ->
        close_loop({:remote, :closed}, parent, debug, state)
    end
  end

  defp handle_error_close(reason, parent, debug, state) do
    send_close_frame(:error, state.conn)

    Process.send_after(self(), :"$websockex_close_timeout", 5000)
    close_loop(reason, parent, debug, state)
  end

  @spec handle_terminate_close(any, pid, any, any) :: no_return
  def handle_terminate_close(reason, parent, debug, state) do
    send_close_frame(:error,  state.conn)

    # I'm not supposed to do this, but I'm going to go ahead and close the
    # socket here. If people complain I'll come up with something else.
    new_conn = WebSockex.Conn.close_socket(state.conn)
    terminate(reason, parent, debug, %{state | conn: new_conn})
  end

  # Frame Sending

  defp sync_send(frame, from, parent, debug, %{conn: conn} = state) do
    res = with {:ok, binary_frame} <- WebSockex.Frame.encode_frame(frame),
          do: WebSockex.Conn.socket_send(conn, binary_frame)

    case res do
      :ok ->
        :gen.reply(from, :ok)
        websocket_loop(parent, debug, state)
      {:error, %WebSockex.ConnError{}} = error ->
        :gen.reply(from, error)
        handle_close(error, parent, debug, state)
      {:error, _} = error ->
        :gen.reply(from, error)
        websocket_loop(parent, debug, state)
    end
  end

  defp send_close_frame(reason, conn) do
    with {:ok, binary_frame} <- build_close_frame(reason),
    do: WebSockex.Conn.socket_send(conn, binary_frame)
  end

  defp build_close_frame({_, :normal}) do
    WebSockex.Frame.encode_frame(:close)
  end
  defp build_close_frame({_, code, msg}) do
    WebSockex.Frame.encode_frame({:close, code, msg})
  end
  defp build_close_frame(:error) do
    WebSockex.Frame.encode_frame({:close, 1011, ""})
  end

  # Connection Handling

  defp init_conn_failure(reason, parent, debug, state, attempt \\ 1) do
    case handle_disconnect(reason, state, attempt) do
      {:ok, new_module_state} ->
        init_failure(reason, parent, debug, %{state | module_state: new_module_state})
      {:reconnect, new_conn, new_module_state} ->
        state = %{state | conn: new_conn, module_state: new_module_state}
        case open_connection(parent, debug, state) do
          {:ok, new_state} ->
            module_init(parent, debug, new_state)
          {:error, new_reason, new_state} ->
            init_conn_failure(new_reason, parent, debug, new_state, attempt+1)
        end
      {:"$EXIT", reason} ->
        init_failure(reason, parent, debug, state)
    end
  end

  defp on_disconnect(reason, parent, debug, state, attempt \\ 1) do
    case handle_disconnect(reason, state, attempt) do
      {:ok, new_module_state} when is_tuple(reason) and elem(reason, 0) == :error ->
        terminate(elem(reason, 1), parent, debug, %{state | module_state: new_module_state})
      {:ok, new_module_state} ->
        terminate(reason, parent, debug, %{state | module_state: new_module_state})
      {:reconnect, new_conn, new_module_state} ->
        state = %{state | conn: new_conn, module_state: new_module_state}
        case open_connection(parent, debug, state) do
          {:ok, new_state} ->
            reconnect(parent, debug, new_state)
          {:error, new_reason, new_state} ->
            on_disconnect(new_reason, parent, debug, new_state, attempt+1)
        end
      {:"$EXIT", reason} ->
       terminate(reason, parent, debug, state)
    end
  end

  defp reconnect(parent, debug, state) do
    result = try_callback(state.module, :handle_connect, [state.conn, state.module_state])

    case result do
      {:ok, new_module_state} ->
        state = Map.merge(state, %{buffer: <<>>,
                                   fragment: nil,
                                   module_state: new_module_state})
         websocket_loop(parent, debug, state)
      {:"$EXIT", reason} ->
        terminate(reason, parent, debug, state)
      badreply ->
        reason =  %WebSockex.BadResponseError{module: state.module,
          function: :handle_connect, args: [state.conn, state.module_state],
          response: badreply}
        terminate(reason, parent, debug, state)
    end
  end

  defp open_connection(parent, debug, %{conn: conn} = state) do
    my_pid = self()
    task = Task.async(fn ->
      with {:ok, conn} <- WebSockex.Conn.open_socket(conn),
           key <- :crypto.strong_rand_bytes(16) |> Base.encode64,
           {:ok, request} <- WebSockex.Conn.build_request(conn, key),
           :ok <- WebSockex.Conn.socket_send(conn, request),
           {:ok, headers} <- WebSockex.Conn.handle_response(conn),
           :ok <- validate_handshake(headers, key)
      do
        :ok = WebSockex.Conn.controlling_process(conn, my_pid)
        :ok = WebSockex.Conn.set_active(conn)
        {:ok, conn}
      end
    end)
    open_loop(parent, debug, Map.put(state, :task, task))
  end

  # Other State Functions

  defp module_init(parent, debug, state) do
    result = try_callback(state.module, :handle_connect, [state.conn, state.module_state])

    case result do
      {:ok, new_module_state} ->
         state.reply_fun.({:ok, self()})
         state = Map.put(state, :module_state, new_module_state)
                 |> Map.delete(:reply_fun)

          websocket_loop(parent, debug, state)
      {:"$EXIT", reason} ->
        state.reply_fun.(reason)
      badreply ->
        reason = {:error, %WebSockex.BadResponseError{module: state.module,
          function: :handle_connect, args: [state.conn, state.module_state],
          response: badreply}}
        state.reply_fun.(reason)
    end
  end

  @spec terminate(any, pid, any, any) :: no_return
  defp terminate(reason, parent, debug, %{conn: %{socket: socket}} = state)
  when not is_nil(socket) do
    handle_terminate_close(reason, parent, debug, state)
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

  defp handle_disconnect(reason, state, attempt) do
    status_map = %{conn: state.conn,
                   reason: reason,
                   attempt_number: attempt}

    result = try_callback(state.module, :handle_disconnect, [status_map, state.module_state])

    case result do
      {:ok, new_state} ->
        {:ok, new_state}
      {:reconnect, new_state} ->
        {:reconnect, state.conn, new_state}
      {:reconnect, new_conn, new_state} ->
        {:reconnect, new_conn, new_state}
      {:"$EXIT", _} = res ->
        res
      badreply ->
        {:"$EXIT", %WebSockex.BadResponseError{module: state.module,
          function: :handle_disconnect, args: [status_map, state.module_state],
          response: badreply}}
    end
  end

  # Helpers (aka everything else)

  defp try_callback(module, function, args) do
    apply(module, function, args)
  catch
    :error, payload ->
      stacktrace = System.stacktrace()
      reason = Exception.normalize(:error, payload, stacktrace)
      {:"$EXIT", {reason, stacktrace}}
    :exit, payload ->
      {:"$EXIT", payload}
  end

  defp init_failure(reason, _parent, _debug, state) do
    state.reply_fun.({:error, reason})
  end

  defp async_init_fun({:ok, _}), do: :noop
  defp async_init_fun(exit_reason), do: exit(exit_reason)

  defp sync_init_fun(parent, {error, stacktrace}) when is_list(stacktrace) do
    :proc_lib.init_ack(parent, {:error, error})
  end
  defp sync_init_fun(parent, reply) do
    :proc_lib.init_ack(parent, reply)
  end

  defp validate_handshake(headers, key) do
    challenge = :crypto.hash(:sha, key <> @handshake_guid) |> Base.encode64

    {_, res} = List.keyfind(headers, "Sec-Websocket-Accept", 0)

    if challenge == res do
      :ok
    else
      {:error, %WebSockex.HandshakeError{response: res, challenge: challenge}}
    end
  end

  defp parse_uri(url) do
    case URI.parse(url) do
      # This is confusing to look at. But it's just a match with multiple guards
      %URI{host: host, port: port, scheme: protocol}
      when is_nil(host)
      when is_nil(port)
      when not protocol in ["ws", "wss"] ->
        {:error, %WebSockex.URLError{url: url}}
      %URI{} = uri ->
        {:ok, uri}
    end
  end
end
