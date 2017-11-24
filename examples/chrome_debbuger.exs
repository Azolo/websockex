defmodule ChromeDebugger do
  use WebSockex

  @moduledoc ~S"""
  Sample usage connecting to a devtools remote-debugging page to orchestrate the browser and receive network events on the socket directly.
  Example Usage With a Chrome Remote Debugging Enabled Instance (or driver), and using Poison to decode/encode the remote-protocol message passing (assuming you have started chrome with a remote debugging port 55171, and have the WebSocket address for the page/tab in question)

  ```
  ChromeDebugger.start("ws://127.0.0.1:55171/devtools/page/18569def-3e03-4d67-a5b9-ca6a0ee0db77", %{port: 55171})
  ```
  """
     
  def start(url, state) do
    {:ok, pid} = WebSockex.start(url, __MODULE__, state)
    WebSockex.send_frame(pid, {:text, Poison.encode!(%{id: 1, method: "Network.enable", params: %{}})})
    WebSockex.send_frame(pid, {:text, Poison.encode!(%{id: 2, method: "Runtime.enable", params: %{}})})
    WebSockex.send_frame(pid, {:text, Poison.encode!(%{id: 3, method: "Page.enable", params: %{}})})
    {:ok, pid}
  end

  def terminate(reason, state) do
    IO.puts("WebSockex for remote debbugging on port #{state.port} terminating with reason: #{inspect reason}")
    exit(:normal)
  end

  def handle_frame({_type, msg}, state) do
    case Poison.decode(msg) do
      {:error, error} ->
        Logger.debug(inspect msg)
        Logger.error(inspect error)
      {:ok, message} ->
        case message["method"] do
          "Network.webSocketFrameReceived" ->
            with true <- message["params"]["response"]["opcode"] == 1,
                 message_pl <- message["params"]["response"]["payloadData"]
              do
              IO.puts("Message from remote-debbuging port #{state.port}: #{inspect message_pl}")
              else
                _ -> :ok
            end
          _ -> :ok
        end
    end
    {:ok, state}
  end
  
end
