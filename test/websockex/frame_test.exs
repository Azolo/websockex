defmodule WebSockex.FrameTest do
  use ExUnit.Case, async: true
  # Frame: (val::bitsize)
  # << fin::1, 0::3, opcode::4, mask::1, payload_len::7 >>
  # << fin::1, 0::3, [1,2,8,9,10]::4, mask::1, payload_len::7 >>
  # << fin::1, 0::3, [1,2]::4, 0::1, 126::7, payload_len::16 >>
  # << fin::1, 0::3, [1,2]::4, 0::1, 127::7, payload_len::64 >>
  # << fin::1, 0::3, opcode::4, 1::1, payload_len::(7-71), masking_key::32 >>

  alias WebSockex.{Frame}

  @ping_frame <<1::1, 0::3, 9::4, 0::1, 0::7>>
  @ping_frame_with_payload <<1::1, 0::3, 9::4, 0::1, 5::7, "Hello">>

  describe "parse_frame" do
    test "returns incomplete when the frame is less than 16 bits" do
      <<part::10, _::bits>> = @ping_frame
      assert Frame.parse_frame(<<part>>) == {:incomplete, <<part>>}
    end

    test "parses a ping frame" do
      assert Frame.parse_frame(@ping_frame) == {%Frame{opcode: :ping}, <<>>}
    end

    test "parses a ping frame with a payload" do
      assert Frame.parse_frame(@ping_frame_with_payload) ==
        {%Frame{opcode: :ping, payload: "Hello"}, <<>>}
    end

    test "returns overflow buffer" do
      <<first::bits-size(16), overflow::bits-size(14), rest::bitstring>> =
        <<@ping_frame, @ping_frame_with_payload>>
      payload = <<first::bits, overflow::bits>>
      assert Frame.parse_frame(payload) == {%Frame{opcode: :ping}, overflow}
      assert Frame.parse_frame(<<overflow::bits, rest::bits>>) ==
        {%Frame{opcode: :ping, payload: "Hello"}, <<>>}
    end
  end
end
