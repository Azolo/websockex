defmodule WebSockex.FrameTest do
  use ExUnit.Case, async: true
  # Frame: (val::bitsize)
  # << fin::1, 0::3, opcode::4, 0::1, payload_len::7 >>
  # << 1::1, 0::3, [8,9,10]::4, 0::1, payload_len::7 >>
  # << 1::1, 0::3, [8,9,10]::4, 0::1, payload_len::7 >>
  # << fin::1, 0::3, [0,1,2]::4, 0::1, payload_len::7 >>
  # << fun::1, 0::3, [0,1,2]::4, 0::1, 126::7, payload_len::16 >>
  # << fin::1, 0::3, [0,1,2]::4, 0::1, 127::7, payload_len::64 >>
  # << fin::1, 0::3, opcode::4, 1::1, payload_len::(7-71), masking_key::32 >>

  @close_frame <<1::1, 0::3, 8::4, 0::1, 0::7>>
  @ping_frame <<1::1, 0::3, 9::4, 0::1, 0::7>>
  @pong_frame <<1::1, 0::3, 10::4, 0::1, 0::7>>
  @close_frame_with_payload <<1::1, 0::3, 8::4, 0::1, 7::7, 1000::16, "Hello">>
  @ping_frame_with_payload <<1::1, 0::3, 9::4, 0::1, 5::7, "Hello">>
  @pong_frame_with_payload <<1::1, 0::3, 10::4, 0::1, 5::7, "Hello">>

  @binary :erlang.term_to_binary(:hello)

  alias WebSockex.{Frame}
  import Bitwise

  def unmask(key, payload, acc \\ <<>>)
  def unmask(_, <<>>, acc), do: acc

  for x <- 1..3 do
    def unmask(<<key::8*unquote(x), _::binary>>, <<payload::8*unquote(x)>>, acc) do
      part = payload ^^^ key
      <<acc::binary, part::8*unquote(x)>>
    end
  end

  def unmask(<<key::8*4>>, <<payload::8*4, rest::binary>>, acc) do
    part = payload ^^^ key
    unmask(<<key::8*4>>, rest, <<acc::binary, part::8*4>>)
  end

  @large_binary <<0::300*8, "Hello">>

  describe "parse_frame" do
    test "returns incomplete when the frame is less than 16 bits" do
      <<part::10, _::bits>> = @ping_frame
      assert Frame.parse_frame(<<part>>) == :incomplete
    end

    test "handles incomplete frames with complete headers" do
      frame = <<1::1, 0::3, 1::4, 0::1, 5::7, "Hello"::utf8>>

      <<part::bits-size(20), rest::bits>> = frame
      assert Frame.parse_frame(part) == :incomplete

      assert Frame.parse_frame(<<part::bits, rest::bits>>) == {:ok, {:text, "Hello"}, <<>>}
    end

    test "handles incomplete continuation large frames" do
      len = 0x5555
      frame = <<1::1, 0::3, 0::4, 0::1, 126::7, len::16, 0::500*8, "Hello">>
      assert Frame.parse_frame(frame) == :incomplete
    end

    test "handles incomplete continuation very large frame" do
      len = 0x5FFFF
      frame = <<1::1, 0::3, 0::4, 0::1, 127::7, len::64, 0::1000*8, "Hello">>
      assert Frame.parse_frame(frame) == :incomplete
    end

    test "handles incomplete text large frames" do
      len = 0x5555
      frame = <<1::1, 0::3, 1::4, 0::1, 126::7, len::16, 0::500*8, "Hello">>
      assert Frame.parse_frame(frame) == :incomplete
    end

    test "handles incomplete text very large frame" do
      len = 0x5FFFF
      frame = <<1::1, 0::3, 1::4, 0::1, 127::7, len::64, 0::1000*8, "Hello">>
      assert Frame.parse_frame(frame) == :incomplete
    end

    test "returns overflow buffer" do
      <<first::bits-size(16), overflow::bits-size(14), rest::bitstring>> =
        <<@ping_frame, @ping_frame_with_payload>>

      payload = <<first::bits, overflow::bits>>
      assert Frame.parse_frame(payload) == {:ok, :ping, overflow}
      assert Frame.parse_frame(<<overflow::bits, rest::bits>>) == {:ok, {:ping, "Hello"}, <<>>}
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
      assert Frame.parse_frame(@close_frame_with_payload) == {:ok, {:close, 1000, "Hello"}, <<>>}
    end

    test "parses a ping frame with a payload" do
      assert Frame.parse_frame(@ping_frame_with_payload) == {:ok, {:ping, "Hello"}, <<>>}
    end

    test "parses a pong frame with a payload" do
      assert Frame.parse_frame(@pong_frame_with_payload) == {:ok, {:pong, "Hello"}, <<>>}
    end

    test "parses a text frame" do
      frame = <<1::1, 0::3, 1::4, 0::1, 5::7, "Hello"::utf8>>
      assert Frame.parse_frame(frame) == {:ok, {:text, "Hello"}, <<>>}
    end

    test "parses a large text frame" do
      string = <<0::5000*8, "Hello">>
      len = byte_size(string)
      frame = <<1::1, 0::3, 1::4, 0::1, 126::7, len::16, string::binary>>
      assert Frame.parse_frame(frame) == {:ok, {:text, string}, <<>>}
    end

    test "parses a very large text frame" do
      string = <<0::80_000*8, "Hello">>
      len = byte_size(string)
      frame = <<1::1, 0::3, 1::4, 0::1, 127::7, len::64, string::binary>>
      assert Frame.parse_frame(frame) == {:ok, {:text, string}, <<>>}
    end

    test "parses a binary frame" do
      len = byte_size(@binary)
      frame = <<1::1, 0::3, 2::4, 0::1, len::7, @binary::bytes>>
      assert Frame.parse_frame(frame) == {:ok, {:binary, @binary}, <<>>}
    end

    test "parses a large binary frame" do
      binary = <<0::5000*8, @binary::binary>>
      len = byte_size(binary)
      frame = <<1::1, 0::3, 2::4, 0::1, 126::7, len::16, binary::binary>>
      assert Frame.parse_frame(frame) == {:ok, {:binary, binary}, <<>>}
    end

    test "parses a very large binary frame" do
      binary = <<0::80_000*8, @binary::binary>>
      len = byte_size(binary)
      frame = <<1::1, 0::3, 2::4, 0::1, 127::7, len::64, binary::binary>>
      assert Frame.parse_frame(frame) == {:ok, {:binary, binary}, <<>>}
    end

    test "parses a text fragment frame" do
      frame = <<0::1, 0::3, 1::4, 0::1, 5::7, "Hello"::utf8>>
      assert Frame.parse_frame(frame) == {:ok, {:fragment, :text, "Hello"}, <<>>}
    end

    test "parses a large text fragment frame" do
      string = <<0::5000*8, "Hello">>
      len = byte_size(string)
      frame = <<0::1, 0::3, 1::4, 0::1, 126::7, len::16, string::binary>>
      assert Frame.parse_frame(frame) == {:ok, {:fragment, :text, string}, <<>>}
    end

    test "parses a very large text fragment frame" do
      string = <<0::80_000*8, "Hello">>
      len = byte_size(string)
      frame = <<0::1, 0::3, 1::4, 0::1, 127::7, len::64, string::binary>>
      assert Frame.parse_frame(frame) == {:ok, {:fragment, :text, string}, <<>>}
    end

    test "parses a binary fragment frame" do
      len = byte_size(@binary)
      frame = <<0::1, 0::3, 2::4, 0::1, len::7, @binary::bytes>>
      assert Frame.parse_frame(frame) == {:ok, {:fragment, :binary, @binary}, <<>>}
    end

    test "parses a large binary fragment frame" do
      binary = <<0::5000*8, @binary::binary>>
      len = byte_size(binary)
      frame = <<0::1, 0::3, 2::4, 0::1, 126::7, len::16, binary::binary>>
      assert Frame.parse_frame(frame) == {:ok, {:fragment, :binary, binary}, <<>>}
    end

    test "parses a very large binary fragment frame" do
      binary = <<0::80_000*8, @binary::binary>>
      len = byte_size(binary)
      frame = <<0::1, 0::3, 2::4, 0::1, 127::7, len::64, binary::binary>>
      assert Frame.parse_frame(frame) == {:ok, {:fragment, :binary, binary}, <<>>}
    end

    test "parses a continuation frame in a fragmented segment" do
      frame = <<0::1, 0::3, 0::4, 0::1, 5::7, "Hello"::utf8>>
      assert Frame.parse_frame(frame) == {:ok, {:continuation, "Hello"}, <<>>}
    end

    test "parses a large continuation frame in a fragmented segment" do
      string = <<0::5000*8, "Hello">>
      len = byte_size(string)
      frame = <<0::1, 0::3, 0::4, 0::1, 126::7, len::16, string::binary>>
      assert Frame.parse_frame(frame) == {:ok, {:continuation, string}, <<>>}
    end

    test "parses a very large continuation frame in a fragmented segment" do
      string = <<0::80_000*8, "Hello">>
      len = byte_size(string)
      frame = <<0::1, 0::3, 0::4, 0::1, 127::7, len::64, string::binary>>
      assert Frame.parse_frame(frame) == {:ok, {:continuation, string}, <<>>}
    end

    test "parses a finish frame in a fragmented segment" do
      frame = <<1::1, 0::3, 0::4, 0::1, 5::7, "Hello"::utf8>>
      assert Frame.parse_frame(frame) == {:ok, {:finish, "Hello"}, <<>>}
    end

    test "parses a large finish frame in a fragmented segment" do
      string = <<0::5000*8, "Hello">>
      len = byte_size(string)
      frame = <<1::1, 0::3, 0::4, 0::1, 126::7, len::16, string::binary>>
      assert Frame.parse_frame(frame) == {:ok, {:finish, string}, <<>>}
    end

    test "parses a very large finish frame in a fragmented segment" do
      string = <<0::80_000*8, "Hello">>
      len = byte_size(string)
      frame = <<1::1, 0::3, 0::4, 0::1, 127::7, len::64, string::binary>>
      assert Frame.parse_frame(frame) == {:ok, {:finish, string}, <<>>}
    end

    test "nonfin control frame returns an error" do
      frame = <<0::1, 0::3, 9::4, 0::1, 0::7>>

      assert Frame.parse_frame(frame) ==
               {:error,
                %WebSockex.FrameError{reason: :nonfin_control_frame, opcode: :ping, buffer: frame}}
    end

    test "large control frames return an error" do
      error = %WebSockex.FrameError{reason: :control_frame_too_large, opcode: :ping}

      frame = <<1::1, 0::3, 9::4, 0::1, 126::7>>
      assert Frame.parse_frame(frame) == {:error, %{error | buffer: frame}}

      frame = <<1::1, 0::3, 9::4, 0::1, 127::7>>
      assert Frame.parse_frame(frame) == {:error, %{error | buffer: frame}}
    end

    test "close frames with data must have atleast 2 bytes of data" do
      frame = <<1::1, 0::3, 8::4, 0::1, 1::7, 0::8>>

      assert Frame.parse_frame(frame) ==
               {:error,
                %WebSockex.FrameError{
                  reason: :close_with_single_byte_payload,
                  opcode: :close,
                  buffer: frame
                }}
    end

    test "Close Frames with improper close codes return an error" do
      frame = <<1::1, 0::3, 8::4, 0::1, 7::7, 5000::16, "Hello">>

      assert Frame.parse_frame(frame) ==
               {:error,
                %WebSockex.FrameError{reason: :invalid_close_code, opcode: :close, buffer: frame}}
    end

    test "Text Frames check for valid UTF-8" do
      frame = <<1::1, 0::3, 1::4, 0::1, 7::7, 0xFFFF::16, "Hello"::utf8>>

      assert Frame.parse_frame(frame) ==
               {:error,
                %WebSockex.FrameError{reason: :invalid_utf8, opcode: :text, buffer: frame}}
    end

    test "Close Frames with payloads check for valid UTF-8" do
      frame = <<1::1, 0::3, 8::4, 0::1, 9::7, 1000::16, 0xFFFF::16, "Hello"::utf8>>

      assert Frame.parse_frame(frame) ==
               {:error,
                %WebSockex.FrameError{reason: :invalid_utf8, opcode: :close, buffer: frame}}
    end
  end

  describe "parse_fragment" do
    test "Errors with two fragment starts" do
      frame0 = {:fragment, :text, "Hello"}
      frame1 = {:fragment, :text, "Goodbye"}

      assert Frame.parse_fragment(frame0, frame1) ==
               {:error,
                %WebSockex.FragmentParseError{
                  reason: :two_start_frames,
                  fragment: frame0,
                  continuation: frame1
                }}
    end

    test "Applies continuation to a text fragment" do
      frame = <<0xFFFF::16, "Hello"::utf8>>
      <<part::binary-size(4), rest::binary>> = frame

      assert Frame.parse_fragment({:fragment, :text, part}, {:continuation, rest}) ==
               {:ok, {:fragment, :text, frame}}
    end

    test "Finishes a text fragment" do
      frame0 = {:fragment, :text, "Hel"}
      frame1 = {:finish, "lo"}
      assert Frame.parse_fragment(frame0, frame1) == {:ok, {:text, "Hello"}}
    end

    test "Errors with invalid utf-8 in a text fragment" do
      frame = <<0xFFFF::16, "Hello"::utf8>>
      <<part::binary-size(4), rest::binary>> = frame

      assert Frame.parse_fragment({:fragment, :text, part}, {:finish, rest}) ==
               {:error,
                %WebSockex.FrameError{reason: :invalid_utf8, opcode: :text, buffer: frame}}
    end

    test "Applies a continuation to a binary fragment" do
      <<part::binary-size(3), rest::binary>> = @binary

      assert Frame.parse_fragment({:fragment, :binary, part}, {:continuation, rest}) ==
               {:ok, {:fragment, :binary, @binary}}
    end

    test "Finishes a binary fragment" do
      <<part::binary-size(3), rest::binary>> = @binary

      assert Frame.parse_fragment({:fragment, :binary, part}, {:finish, rest}) ==
               {:ok, {:binary, @binary}}
    end
  end

  describe "encode_frame" do
    test "encodes a ping frame" do
      assert {:ok, <<1::1, 0::3, 9::4, 1::1, 0::7, _::32>>} = Frame.encode_frame(:ping)
    end

    test "encodes a ping frame with a payload" do
      payload = "A longer but different string."
      len = byte_size(payload)

      assert {:ok,
              <<1::1, 0::3, 9::4, 1::1, ^len::7, mask::bytes-size(4),
                masked_payload::binary-size(len)>>} = Frame.encode_frame({:ping, payload})

      assert unmask(mask, masked_payload) == payload
    end

    test "encodes a pong frame" do
      assert {:ok, <<1::1, 0::3, 10::4, 1::1, 0::7, _::32>>} = Frame.encode_frame(:pong)
    end

    test "encodes a pong frame with a payload" do
      payload = "No"
      len = byte_size(payload)

      assert {:ok,
              <<1::1, 0::3, 10::4, 1::1, ^len::7, mask::bytes-size(4),
                masked_payload::binary-size(len)>>} = Frame.encode_frame({:pong, payload})

      assert unmask(mask, masked_payload) == payload
    end

    test "encodes a close frame" do
      assert {:ok, <<1::1, 0::3, 8::4, 1::1, 0::7, _::32>>} = Frame.encode_frame(:close)
    end

    test "encodes a close frame with a payload" do
      payload = "Hello"
      len = byte_size(<<1000::16, payload::binary>>)

      assert {:ok,
              <<1::1, 0::3, 8::4, 1::1, ^len::7, mask::bytes-size(4),
                masked_payload::binary-size(len)>>} = Frame.encode_frame({:close, 1000, payload})

      assert unmask(mask, masked_payload) == <<1000::16, payload::binary>>
    end

    test "returns an error with large ping frame" do
      assert Frame.encode_frame({:ping, @large_binary}) ==
               {:error,
                %WebSockex.FrameEncodeError{
                  reason: :control_frame_too_large,
                  frame_type: :ping,
                  frame_payload: @large_binary
                }}
    end

    test "returns an error with large pong frame" do
      assert Frame.encode_frame({:pong, @large_binary}) ==
               {:error,
                %WebSockex.FrameEncodeError{
                  reason: :control_frame_too_large,
                  frame_type: :pong,
                  frame_payload: @large_binary
                }}
    end

    test "returns an error with large close frame" do
      assert Frame.encode_frame({:close, 1000, @large_binary}) ==
               {:error,
                %WebSockex.FrameEncodeError{
                  reason: :control_frame_too_large,
                  frame_type: :close,
                  frame_payload: @large_binary,
                  close_code: 1000
                }}
    end

    test "returns an error with close code out of range" do
      assert Frame.encode_frame({:close, 5838, "Hello"}) ==
               {:error,
                %WebSockex.FrameEncodeError{
                  reason: :close_code_out_of_range,
                  frame_type: :close,
                  frame_payload: "Hello",
                  close_code: 5838
                }}
    end

    test "encodes a text frame" do
      payload = "Lemon Pies are Pies."
      len = byte_size(payload)

      assert {:ok,
              <<1::1, 0::3, 1::4, 1::1, ^len::7, mask::bytes-size(4), masked_payload::binary>>} =
               Frame.encode_frame({:text, payload})

      assert unmask(mask, masked_payload) == payload
    end

    test "encodes a large text frame" do
      payload = <<0::300*8, "Lemon Pies are Pies.">>
      len = byte_size(payload)

      assert {:ok,
              <<1::1, 0::3, 1::4, 1::1, 126::7, ^len::16, mask::bytes-size(4),
                masked_payload::binary>>} = Frame.encode_frame({:text, payload})

      assert unmask(mask, masked_payload) == payload
    end

    test "encodes a very large text frame" do
      payload = <<0::0xFFFFF*8, "Lemon Pies are Pies.">>
      len = byte_size(payload)

      assert {:ok,
              <<1::1, 0::3, 1::4, 1::1, 127::7, ^len::64, mask::bytes-size(4),
                masked_payload::binary>>} = Frame.encode_frame({:text, payload})

      assert unmask(mask, masked_payload) == payload
    end

    test "encodes a binary frame" do
      payload = @binary
      len = byte_size(payload)

      assert {:ok,
              <<1::1, 0::3, 2::4, 1::1, ^len::7, mask::bytes-size(4), masked_payload::binary>>} =
               Frame.encode_frame({:binary, payload})

      assert unmask(mask, masked_payload) == payload
    end

    test "encodes a large binary frame" do
      payload = <<0::300*8, @binary::binary>>
      len = byte_size(payload)

      assert {:ok,
              <<1::1, 0::3, 2::4, 1::1, 126::7, ^len::16, mask::bytes-size(4),
                masked_payload::binary>>} = Frame.encode_frame({:binary, payload})

      assert unmask(mask, masked_payload) == payload
    end

    test "encodes a very large binary frame" do
      payload = <<0::0xFFFFF*8, @binary::binary>>
      len = byte_size(payload)

      assert {:ok,
              <<1::1, 0::3, 2::4, 1::1, 127::7, ^len::64, mask::bytes-size(4),
                masked_payload::binary>>} = Frame.encode_frame({:binary, payload})

      assert unmask(mask, masked_payload) == payload
    end

    test "encodes a text fragment frame" do
      payload = "Lemon Pies are Pies."
      len = byte_size(payload)

      assert {:ok,
              <<0::1, 0::3, 1::4, 1::1, ^len::7, mask::bytes-size(4), masked_payload::binary>>} =
               Frame.encode_frame({:fragment, :text, payload})

      assert unmask(mask, masked_payload) == payload
    end

    test "encodes a large text fragment frame" do
      payload = <<0::300*8, "Lemon Pies are Pies.">>
      len = byte_size(payload)

      assert {:ok,
              <<0::1, 0::3, 1::4, 1::1, 126::7, ^len::16, mask::bytes-size(4),
                masked_payload::binary>>} = Frame.encode_frame({:fragment, :text, payload})

      assert unmask(mask, masked_payload) == payload
    end

    test "encodes a very large text fragment frame" do
      payload = <<0::0xFFFFF*8, "Lemon Pies are Pies.">>
      len = byte_size(payload)

      assert {:ok,
              <<0::1, 0::3, 1::4, 1::1, 127::7, ^len::64, mask::bytes-size(4),
                masked_payload::binary>>} = Frame.encode_frame({:fragment, :text, payload})

      assert unmask(mask, masked_payload) == payload
    end

    test "encodes a binary fragment frame" do
      payload = @binary
      len = byte_size(payload)

      assert {:ok,
              <<0::1, 0::3, 2::4, 1::1, ^len::7, mask::bytes-size(4), masked_payload::binary>>} =
               Frame.encode_frame({:fragment, :binary, payload})

      assert unmask(mask, masked_payload) == payload
    end

    test "encodes a large binary fragment frame" do
      payload = <<0::300*8, @binary::binary>>
      len = byte_size(payload)

      assert {:ok,
              <<0::1, 0::3, 2::4, 1::1, 126::7, ^len::16, mask::bytes-size(4),
                masked_payload::binary>>} = Frame.encode_frame({:fragment, :binary, payload})

      assert unmask(mask, masked_payload) == payload
    end

    test "encodes a very large binary fragment frame" do
      payload = <<0::0xFFFFF*8, @binary::binary>>
      len = byte_size(payload)

      assert {:ok,
              <<0::1, 0::3, 2::4, 1::1, 127::7, ^len::64, mask::bytes-size(4),
                masked_payload::binary>>} = Frame.encode_frame({:fragment, :binary, payload})

      assert unmask(mask, masked_payload) == payload
    end

    test "encodes a continuation frame" do
      payload = "Lemon Pies are Pies."
      len = byte_size(payload)

      assert {:ok,
              <<0::1, 0::3, 0::4, 1::1, ^len::7, mask::bytes-size(4), masked_payload::binary>>} =
               Frame.encode_frame({:continuation, payload})

      assert unmask(mask, masked_payload) == payload
    end

    test "encodes a large continuation frame" do
      payload = <<0::300*8, "Lemon Pies are Pies.">>
      len = byte_size(payload)

      assert {:ok,
              <<0::1, 0::3, 0::4, 1::1, 126::7, ^len::16, mask::bytes-size(4),
                masked_payload::binary>>} = Frame.encode_frame({:continuation, payload})

      assert unmask(mask, masked_payload) == payload
    end

    test "encodes a very large continuation frame" do
      payload = <<0::0xFFFFF*8, "Lemon Pies are Pies.">>
      len = byte_size(payload)

      assert {:ok,
              <<0::1, 0::3, 0::4, 1::1, 127::7, ^len::64, mask::bytes-size(4),
                masked_payload::binary>>} = Frame.encode_frame({:continuation, payload})

      assert unmask(mask, masked_payload) == payload
    end

    test "encodes a finish to a fragmented segment" do
      payload = "Lemon Pies are Pies."
      len = byte_size(payload)

      assert {:ok,
              <<1::1, 0::3, 0::4, 1::1, ^len::7, mask::bytes-size(4), masked_payload::binary>>} =
               Frame.encode_frame({:finish, payload})

      assert unmask(mask, masked_payload) == payload
    end

    test "encodes a large finish to a fragmented segment" do
      payload = <<0::300*8, "Lemon Pies are Pies.">>
      len = byte_size(payload)

      assert {:ok,
              <<1::1, 0::3, 0::4, 1::1, 126::7, ^len::16, mask::bytes-size(4),
                masked_payload::binary>>} = Frame.encode_frame({:finish, payload})

      assert unmask(mask, masked_payload) == payload
    end

    test "encodes a very large finish to a fragmented segment" do
      payload = <<0::0xFFFFF*8, "Lemon Pies are Pies.">>
      len = byte_size(payload)

      assert {:ok,
              <<1::1, 0::3, 0::4, 1::1, 127::7, ^len::64, mask::bytes-size(4),
                masked_payload::binary>>} = Frame.encode_frame({:finish, payload})

      assert unmask(mask, masked_payload) == payload
    end
  end
end
