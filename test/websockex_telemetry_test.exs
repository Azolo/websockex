defmodule WebSockexTelemetryTest do
  use ExUnit.Case, async: false

  if WebSockex.Utils.otp_release() >= 21 do
    describe "telemetry" do
      alias WebSockex.TestClient

      setup context do
        unless context.telemetry_event do
          raise "Please set a :telemetry_event to subscribe to, as tag in your telemetry based tests"
        end

        this = self()
        handler_id = [:test] ++ context.telemetry_event

        :telemetry.attach(
          handler_id,
          context.telemetry_event,
          fn _, measurements, metadata, _ ->
            send(this, %{measurements: measurements, metadata: metadata})
          end,
          %{}
        )

        {:ok, {_, server_ref, url}} = WebSockex.TestServer.start(self())

        {:ok, pid} = TestClient.start(url, %{catch_text: self()})

        on_exit(fn ->
          :telemetry.detach(handler_id)
          Process.exit(pid, :kill)
          WebSockex.TestServer.shutdown(server_ref)
        end)

        server_pid = WebSockex.TestServer.receive_socket_pid()

        Map.merge(context, %{pid: pid, server_pid: server_pid, url: url, server_ref: server_ref})
      end

      @tag telemetry_event: [:websockex, :connected]
      test "emits an event on connections" do
        assert_receive %{
          measurements: _,
          metadata: metadata
        }

        assert WebSockex.TestClient == metadata.module
        assert metadata.conn
      end

      @tag telemetry_event: [:websockex, :terminate]
      test "emits an event on terminations", context do
        send(context.pid, :bad_reply)

        assert_receive %{
          measurements: _,
          metadata: metadata
        }

        assert WebSockex.TestClient == metadata.module
        assert metadata.conn
        assert metadata.reason
      end

      @tag telemetry_event: [:websockex, :disconnected]
      test "emits an event on disconnections", context do
        send(context.server_pid, :close)

        assert_receive %{
          measurements: _,
          metadata: metadata
        }

        assert WebSockex.TestClient == metadata.module
        assert metadata.conn
        assert metadata.reason
      end

      @tag telemetry_event: [:websockex, :frame, :sent]
      test "emits an event on frames sent", context do
        assert WebSockex.send_frame(context.pid, :ping) == :ok

        assert_receive %{
          measurements: _,
          metadata: metadata
        }

        assert WebSockex.TestClient == metadata.module
        assert metadata.conn
        assert metadata.frame == :ping
      end

      @tag telemetry_event: [:websockex, :frame, :received]
      test "emits an event on frames received", context do
        frame = {:text, "hello"}

        send(context.server_pid, {:send, frame})

        assert_receive %{
          measurements: _,
          metadata: metadata
        }

        assert WebSockex.TestClient == metadata.module
        assert metadata.conn
        assert metadata.frame == frame
      end
    end
  end
end
