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
    unmask(<<key>>, rest, <<acc::binary, part::8*4>>)
  end

  @large_binary <<0::300*8, "Hello">>

  test "parse_frame is delegated to parser" do
    frame = <<1::1, 0::3, 9::4, 0::1, 0::7>>
    assert Frame.parse_frame(frame) == Frame.Parser.parse_frame(frame)
  end

  test "parse_fragment is delegated to Parser" do
    frame0 = {:fragment, :text, "Hel"}
    frame1 = {:finish, "lo"}
    assert Frame.parse_fragment(frame0, frame1) ==
      Frame.Parser.parse_fragment(frame0, frame1)
  end

  describe "encode_frame" do
    test "encodes a ping frame" do
      assert {:ok, <<1::1, 0::3, 9::4, 1::1, 0::7, _::32>>} =
        Frame.encode_frame(:ping)
    end
    test "encodes a ping frame with a payload" do
      payload = "Hello"
      len = byte_size(payload)
      assert {:ok, <<1::1, 0::3, 9::4, 1::1, ^len::7, mask::bytes-size(4), masked_payload::binary-size(len)>>} =
        Frame.encode_frame({:ping, payload})
      assert unmask(mask, masked_payload) == payload
    end

    test "raises an error with large ping frame" do
      assert Frame.encode_frame({:ping, @large_binary}) ==
        {:error,
          %WebSockex.FrameEncodeError{reason: :control_frame_too_large,
                                      frame_type: :ping,
                                      frame_payload: @large_binary}}
    end
  end
end
