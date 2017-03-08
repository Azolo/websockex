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
end
