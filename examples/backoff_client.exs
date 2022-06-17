defmodule BackoffClient do
  use WebSockex
  require Logger

  def start_link(opts \\ []) do
    WebSockex.start_link("wss://echo.websocket.org/?encoding=text", __MODULE__, :fake_state, opts)
  end

  @spec echo(pid, String.t) :: :ok
  def echo(client, message) do
    Logger.info("Sending message: #{message}")
    WebSockex.send_frame(client, {:text, message})
  end

  def handle_connect(_conn, state) do
    Logger.info("Connected!")
    {:ok, state}
  end

  def handle_frame({:text, "Can you please reply yourself?" = msg}, :fake_state) do
    Logger.info("Received Message: #{msg}")
    msg = "Sure can!"
    ref = make_ref()
    Logger.info("Sending message: #{msg} with ref #{inspect(ref)}")
    {:reply, {:text, msg}, ref, :fake_state}
  end
  def handle_frame({:text, "Close the things!" = msg}, :fake_state) do
    Logger.info("Received Message: #{msg}")
    {:close, :fake_state}
  end
  def handle_frame({:text, msg}, :fake_state) do
    Logger.info("Received Message: #{msg}")
    {:ok, :fake_state}
  end

  def handle_disconnect(%{attempt_number: attempt, reason: reason}, state) do
    Logger.warning("Websocket connection failed because: #{inspect(reason)}. Attempt: #{attempt}")
    {:backoff, 1_000, state}
  end

  def handle_send_result(result, frame, send_key, state) do
    Logger.debug("Send result for key: #{inspect(send_key)}, frame: #{inspect(frame)}, result: #{inspect(result)}")
    {:ok, state}
  end
end

{:ok, pid} = BackoffClient.start_link()

BackoffClient.echo(pid, "Yo Homies!")
BackoffClient.echo(pid, "This and That!")
BackoffClient.echo(pid, "Can you please reply yourself?")

Process.sleep 1000

BackoffClient.echo(pid, "Close the things!")

Process.sleep 1500
