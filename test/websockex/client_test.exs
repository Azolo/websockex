defmodule WebSockex.ClientTest do
  use ExUnit.Case, async: true

  defmodule TestClient do
    use WebSockex.Client

    def start_link(state) do
      WebSockex.Client.start_link(__MODULE__, state)
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
  end

  setup do
    {:ok, pid} = TestClient.start_link(:ok)

    [pid: pid]
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
end
