defmodule WebSockex.Utils do
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
            "*DBG* #{inspect name} closed remotely with reason: #{inspect reason}")
  end
  defp print_event(io_dev, {:close, :local, reason}, %{name: name}) do
    IO.puts(io_dev,
            "*DBG* #{inspect name} closed locally with reason: #{inspect reason}")
  end
  defp print_event(io_dev, {:close, :error, error}, %{name: name}) do
    IO.puts(io_dev,
            "*DBG* #{inspect name} closing due to error: #{inspect error}")
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
            "*DBG* #{inspect name} sending close frame: #{inspect frame}")
  end
  defp print_event(io_dev, :reconnect, %{name: name}) do
    IO.puts(io_dev,
            "*DBG* #{inspect name} attempting to reconnect")
  end
  defp print_event(io_dev, :connect, %{name: name}) do
    IO.puts(io_dev,
            "*DBG* #{inspect name} attempting to connect")
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
