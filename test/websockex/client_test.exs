defmodule WebSockex.ClientTest do
  use ExUnit.Case, async: true

  defmodule TestClient do
    use WebSockex.Client

    def start_link(url, state) do
      WebSockex.Client.start_link(url, __MODULE__, state)
    end

    def handle_cast({:pid_reply, pid}, state) do
      send(pid, :cast)
      {:ok, state}
    end
    def handle_cast({:set_state, state}, _state), do: {:ok, state}
    def handle_cast({:get_state, pid}, state) do
      send(pid, state)
      {:ok, state}
    end

    def handle_info({:pid_reply, pid}, state) do
      send(pid, :info)
      {:ok, state}
    end

    def handle_info(:bad_reply, _) do
      :lemon_pie
    end
  end

  setup do
    {:ok, {server_ref, url}} = WebSockex.TestServer.start(self())

    on_exit fn -> WebSockex.TestServer.shutdown(server_ref) end

    {:ok, pid} = TestClient.start_link(url, :ok)

    [pid: pid, url: url]
  end

  test "handle changes state", context do
    rand_number = :rand.uniform(1000)

    WebSockex.Client.cast(context.pid, {:get_state, self()})
    refute_receive ^rand_number

    WebSockex.Client.cast(context.pid, {:set_state, rand_number})
    WebSockex.Client.cast(context.pid, {:get_state, self()})
    assert_receive ^rand_number
  end

  test "handle_cast", context do
    WebSockex.Client.cast(context.pid, {:pid_reply, self()})

    assert_receive :cast
  end

  test "handle_info", context do
    send(context.pid, {:pid_reply, self()})

    assert_receive :info
  end

  test "informative error with bad url" do
    assert TestClient.start_link("lemon_pie", :ok) == {:error, %WebSockex.URLError{url: "lemon_pie"}}
  end

  test "common_handle exits with a BadResponseError", context do
    Process.flag(:trap_exit, true)
    send(context.pid, :bad_reply)
    assert_receive {:EXIT, _, {%WebSockex.BadResponseError{}, _}}
  end
end
