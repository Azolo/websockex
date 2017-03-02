defmodule WebSockex.FrameTest do
  use ExUnit.Case, async: true
  # Frame: (val::bitsize)
  # << fin::1, 0::3, opcode::4, mask::1, payload_len::7 >>
  # << fin::1, 0::3, [1,2,8,9,10]::4, mask::1, payload_len::7 >>
  # << fin::1, 0::3, [1,2]::4, 0::1, 126::7, payload_len::16 >>
  # << fin::1, 0::3, [1,2]::4, 0::1, 127::7, payload_len::64 >>
  # << fin::1, 0::3, opcode::4, 1::1, payload_len::(7-71), masking_key::32 >>

  alias WebSockex.{Frame}

  @close_frame <<1::1, 0::3, 8::4, 0::1, 0::7>>
  @ping_frame <<1::1, 0::3, 9::4, 0::1, 0::7>>
  @pong_frame <<1::1, 0::3, 10::4, 0::1, 0::7>>
  @close_frame_with_payload <<1::1, 0::3, 8::4, 0::1, 7::7, 1000::16, "Hello">>
  @ping_frame_with_payload <<1::1, 0::3, 9::4, 0::1, 5::7, "Hello">>
  @pong_frame_with_payload <<1::1, 0::3, 10::4, 0::1, 5::7, "Hello">>

  @binary :erlang.term_to_binary :hello
  @binary_size byte_size @binary

  @text_frame <<1::1, 0::3, 1::4, 0::1, 5::7, "Hello"::utf8>>
  @binary_frame <<1::1, 0::3, 2::4, 0::1, @binary_size::7, @binary::bytes>>

  describe "parse_frame" do
    test "returns incomplete when the frame is less than 16 bits" do
      <<part::10, _::bits>> = @ping_frame
      assert Frame.parse_frame(<<part>>) == {:incomplete, <<part>>}
    end
    test "handles incomplete frames with complete headers" do
      <<part::bits-size(20), rest::bits>> = @text_frame
      assert Frame.parse_frame(part) == {:incomplete, part}

      assert Frame.parse_frame(<<part::bits, rest::bits>>) ==
        {:ok, {:text, "Hello"}, <<>>}
    end
    test "returns overflow buffer" do
      <<first::bits-size(16), overflow::bits-size(14), rest::bitstring>> =
        <<@ping_frame, @ping_frame_with_payload>>
      payload = <<first::bits, overflow::bits>>
      assert Frame.parse_frame(payload) == {:ok, :ping, overflow}
      assert Frame.parse_frame(<<overflow::bits, rest::bits>>) ==
        {:ok, {:ping, "Hello"}, <<>>}
    end

    test "parses a close frame" do
      assert Frame.parse_frame(@close_frame) == {:ok, :close, <<>>}
    end
    test "parses a ping frame" do
      assert Frame.parse_frame(@ping_frame) == {:ok, :ping, <<>>}
    end
    test "parses a pong frame" do
      assert Frame.parse_frame(@pong_frame) == {:ok, :pong, <<>>}
    end

    test "parses a close frame with a payload" do
      assert Frame.parse_frame(@close_frame_with_payload) ==
        {:ok, {:close, 1000, "Hello"}, <<>>}
    end
    test "parses a ping frame with a payload" do
      assert Frame.parse_frame(@ping_frame_with_payload) ==
        {:ok, {:ping, "Hello"}, <<>>}
    end
    test "parses a pong frame with a payload" do
      assert Frame.parse_frame(@pong_frame_with_payload) ==
        {:ok, {:pong, "Hello"}, <<>>}
    end

    test "parses a text frame" do
      assert Frame.parse_frame(@text_frame) ==
        {:ok, {:text, "Hello"}, <<>>}
    end
    test "parses a binary frame" do
      assert Frame.parse_frame(@binary_frame) ==
        {:ok, {:binary, @binary}, <<>>}
    end

    test "nonfin control frame returns an error" do
      frame = <<0::1, 0::3, 9::4, 0::1, 0::7>>
      assert Frame.parse_frame(frame) ==
        {:error,
          %WebSockex.FrameError{reason: :nonfin_control_frame,
                                opcode: :ping,
                                buffer: frame}}
    end
    test "large control frames return an error" do
      error = %WebSockex.FrameError{reason: :control_frame_too_large,
                                    opcode: :ping}

      frame = <<1::1, 0::3, 9::4, 0::1, 126::7>>
      assert Frame.parse_frame(frame) ==
        {:error, %{error | buffer: frame}}

      frame = <<1::1, 0::3, 9::4, 0::1, 127::7>>
      assert Frame.parse_frame(frame) ==
        {:error, %{error | buffer: frame}}
    end

    test "close frames with data must have atleast 2 bytes of data" do
      frame = <<1::1, 0::3, 8::4, 0::1, 1::7, 0::8>>
      assert Frame.parse_frame(frame) ==
        {:error,
          %WebSockex.FrameError{reason: :close_with_single_byte_payload,
                                opcode: :close,
                                buffer: frame}}
    end

    test "Text Frames check for valid UTF-8" do
      frame = <<1::1, 0::3, 1::4, 0::1, 7::7, 0xFFFF::16, "Hello"::utf8>>
      assert Frame.parse_frame(frame) ==
        {:error, %WebSockex.FrameError{reason: :invalid_utf8,
                                       opcode: :text,
                                       buffer: frame}}
    end

    test "Close Frames with payloads check for valid UTF-8" do
      frame = <<1::1, 0::3, 8::4, 0::1, 9::7, 1000::16, 0xFFFF::16, "Hello"::utf8>>
      assert Frame.parse_frame(frame) ==
        {:error, %WebSockex.FrameError{reason: :invalid_utf8,
                                       opcode: :close,
                                       buffer: frame}}
    end
  end
end
