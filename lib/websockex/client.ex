defmodule WebSockex.Client do
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

  @typedoc """
  The reason given and sent to the server when locally closing a connection.

  A `:normal` reason is the same as a `1000` reason.
  """
  @type close_reason :: {:local | :remote, :normal | integer | close_message}

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

  @optional_callbacks [handle_disconnect: 2, terminate: 2, code_change: 3]

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
      def terminate(_close_reason, _state), do: :ok

      @doc false
      def code_change(_old_vsn, state, _extra), do: {:ok, state}

      defoverridable [init: 1, handle_msg: 2, handle_cast: 2, handle_info: 2,
                      handle_disconnect: 2, terminate: 2, code_change: 3]
    end
  end

  def start_link(url, module, state) do
    case URI.parse(url) do
      %URI{host: host, port: port, scheme: protocol} = uri
      when is_nil(host)
      when is_nil(port)
      when not protocol in ["ws", "wss"] ->
        # TODO: Make this better
        {:error, {:bad_uri, uri}}
      %URI{} = uri ->
        :proc_lib.start_link(__MODULE__, :init, [uri, module, state])
      {:error, error} ->
        {:error, error}
    end
  end

  def cast(socket, message) do
    send(socket, {:"$websockex_cast", message})
    :ok
  end

  def init(uri, module, state) do
    {:ok, conn} = WebSockex.Conn.connect(uri)

    :proc_lib.init_ack({:ok, self()})
    websocket_loop(%{conn: conn, module: module, module_state: state})
  end

  defp websocket_loop(state) do
    receive do
      {:"$websockex_cast", msg} ->
        common_handle({:handle_cast, msg}, state)
      msg ->
        common_handle({:handle_info, msg}, state)
    end
  end

  defp common_handle({function, msg}, state) do
    case apply(state.module, function, [msg, state.module_state]) do
          {:ok, new_state} ->
            websocket_loop(%{state | module_state: new_state})
          {:reply, _message, _new_state} ->
            raise "Not Implemented"
          {:close, _close_message, _new_state} ->
            raise "Not Implemented"
    end
  end
end
