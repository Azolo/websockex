defmodule WebSockex.Utils do
  @moduledoc false

  # Startup

  def spawn(link, conn, module, state, opts) do
    case List.keyfind(opts, :name, 0) do
      {:name, name} ->
        case whereis(name) do
          nil ->
            do_spawn(link, [self(), name, conn, module, state, opts])
          pid ->
            {:error, {:already_started, pid}}
        end
      nil ->
        do_spawn(link, [self(), conn, module, state, opts])
    end
  end

  defp do_spawn(:link, args) do
    :proc_lib.start_link(WebSockex, :init, args)
  end
  defp do_spawn(:no_link, args) do
    :proc_lib.start(WebSockex, :init, args)
  end

  # Named Processes

  def register({:global, name}), do: register({:via, :global, name})
  def register({:via, mod, name} = where_tup) do
    case mod.register_name(name, self()) do
      :yes -> true
      :no -> whereis(where_tup)
    end
  end
  def register(name) do
    try do
      Process.register(self(), name)
    catch
      :error, _ ->
        {:error, {:already_started, Process.whereis(name)}}
    end
  end

  def send({:global, name}, msg), do: WebSockex.Utils.send({:via, :global, name}, msg)
  def send({:via, mod, name}, msg) do
    mod.send(name, msg)
  end
  def send(dest, msg) do
    Kernel.send(dest, msg)
  end

  def whereis({:global, name}), do: whereis({:via, :global, name})
  def whereis({:via, mod, name}) do
    case mod.whereis_name(name) do
      :undefined -> nil
      other -> other
    end
  end
  def whereis(name), do: Process.whereis(name)

  # Debugging

  def sys_debug([], _, _), do: []
  def sys_debug(debug, event, state) do
    :sys.handle_debug(debug, &print_event/3, state, event)
  end

  defp print_event(io_dev, {:in, :frame, frame}, %{name: name}) do
    IO.puts(io_dev,
            "*DBG* #{inspect name} received frame: #{inspect frame}")
  end
  defp print_event(io_dev, {:in, :completed_fragment, frame}, %{name: name}) do
    IO.puts(io_dev,
            "*DBG* #{inspect name} completed fragmented frame: #{inspect frame}")
  end
  defp print_event(io_dev, {:in, :cast, msg}, %{name: name}) do
    IO.puts(io_dev,
            "*DBG* #{inspect name} received cast msg: #{inspect msg}")
  end
  defp print_event(io_dev, {:in, :msg, msg}, %{name: name}) do
    IO.puts(io_dev,
            "*DBG* #{inspect name} received msg: #{inspect msg}")
  end
  defp print_event(io_dev, {:reply, func, frame}, %{name: name}) do
    IO.puts(io_dev,
            "*DBG* #{inspect name} replying from #{inspect func} with #{inspect frame}")
  end
  defp print_event(io_dev, {:close, :remote, :unexpected}, %{name: name}) do
    IO.puts(io_dev,
            "*DBG* #{inspect name} had the connection closed unexpectedly by the remote server")
  end
  defp print_event(io_dev, {:close, :remote, reason}, %{name: name}) do
    IO.puts(io_dev,
            "*DBG* #{inspect name} closing with the remote reason: #{inspect reason}")
  end
  defp print_event(io_dev, {:close, :local, reason}, %{name: name}) do
    IO.puts(io_dev,
            "*DBG* #{inspect name} closing with local reason: #{inspect reason}")
  end
  defp print_event(io_dev, {:close, :error, error}, %{name: name}) do
    IO.puts(io_dev,
            "*DBG* #{inspect name} closing due to error: #{inspect error}")
  end
  defp print_event(io_dev, :closed, %{name: name}) do
    IO.puts(io_dev,
            "*DBG* #{inspect name} closed the connection sucessfully")
  end
  defp print_event(io_dev, :timeout_closed, %{name: name}) do
    IO.puts(io_dev,
            "*DBG* #{inspect name} forcefully closed the connection because the server was taking too long close")
  end
  defp print_event(io_dev, {:socket_out, :close, :error}, %{name: name}) do
    IO.puts(io_dev,
            "*DBG* #{inspect name} sending error close frame: {:close, 1011, \"\"}")
  end
  defp print_event(io_dev, {:socket_out, :close, frame}, %{name: name}) do
    IO.puts(io_dev,
            "*DBG* #{inspect name} sending close frame: #{inspect frame}")
  end
  defp print_event(io_dev, {:socket_out, :sync_send, frame}, %{name: name}) do
    IO.puts(io_dev,
            "*DBG* #{inspect name} sending frame: #{inspect frame}")
  end
  defp print_event(io_dev, :reconnect, %{name: name}) do
    IO.puts(io_dev,
            "*DBG* #{inspect name} attempting to reconnect")
  end
  defp print_event(io_dev, :connect, %{name: name}) do
    IO.puts(io_dev,
            "*DBG* #{inspect name} attempting to connect")
  end
  defp print_event(io_dev, :connected, %{name: name}) do
    IO.puts(io_dev,
            "*DBG* #{inspect name} sucessfully connected")
  end
  defp print_event(io_dev, :reconnected, %{name: name}) do
    IO.puts(io_dev,
            "*DBG* #{inspect name} sucessfully reconnected")
  end

  def parse_debug_options(name, options) do
    case List.keyfind(options, :debug, 0) do
      {:debug, opts} ->
        try do
          :sys.debug_options(opts)
        catch
          _,_ ->
            :error_logger.format('~p: ignoring bad debug options ~p~n',
                                 [name, opts])
            []
        end
      _ -> []
    end
  end
end
