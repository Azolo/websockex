defmodule WebSockex.FrameTest do
  use ExUnit.Case, async: true
  # Frame: (val::bitsize)
  # << fin::1, 0::3, opcode::4, mask::1, payload_len::7 >>
  # << fin::1, 0::3, [1,2,8,9,10]::4, mask::1, payload_len::7 >>
  # << fin::1, 0::3, [1,2]::4, 0::1, 126::7, payload_len::16 >>
  # << fin::1, 0::3, [1,2]::4, 0::1, 127::7, payload_len::64 >>
  # << fin::1, 0::3, opcode::4, 1::1, payload_len::(7-71), masking_key::32 >>

  @ping_frame <<1::1, 0::3, 9::4, 0::1, 0::7>>
  @ping_with_payload_frame <<1::1, 0::3, 9::4, 0::1, 5::7, "Hello">>

  describe "parse_frame" do
    test "returns incomplete when the frame is less than 16 bits" do
      <<part::10, _::bits>> = @ping_frame
      assert WebSockex.Frame.parse_frame(<<part>>) == {:incomplete, <<part>>}
    end
  end
end
