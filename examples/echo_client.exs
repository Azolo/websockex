defmodule EchoClient do
  use WebSockex
  require Logger

  def start_link do
    WebSockex.start_link("wss://echo.websocket.org/?encoding=text", __MODULE__, :state)
  end

  @spec echo(pid, String.t) :: :ok
  def echo(client, message) do
    Logger.info("Sending message: #{message}")
    WebSockex.send_frame(client, {:text, message})
  end

  @spec send_frame(pid, WebSockex.frame) :: :ok
  def send_frame(pid, {:text, msg} = frame) do
    Logger.info("Sending message: #{msg}")
    WebSockex.send_frame(pid, frame)
  end

  def handle_frame({:text, "Close the things!" = msg}, :state) do
    Logger.info("Received Message: #{msg}")
    {:close, :state}
  end
  def handle_frame({:text, msg}, :state) do
    Logger.info("Received Message: #{msg}")
    {:ok, :state}
  end

  def handle_disconnect({:local, reason}, state) do
    Logger.info("Local close with reason: #{inspect reason}")
    {:ok, state}
  end
  def handle_disconnect(reason, state) do
    super(reason, state)
  end
end

{:ok, pid} = EchoClient.start_link()

EchoClient.send_frame(pid, {:text, "Yo Homies!"})
EchoClient.send_frame(pid, {:text, "This and That!"})

Process.sleep 500

EchoClient.send_frame(pid, {:text, "Close the things!"})

Process.sleep 1500
