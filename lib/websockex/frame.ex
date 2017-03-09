defmodule WebSockex.Frame do
  @moduledoc """
  Functions for parsing and encoding frames.
  """

  @type opcode :: :text | :binary | :close | :ping | :pong
  @type close_code :: 1000..4999

  @typedoc "The incomplete or unhandled remainder of a binary"
  @type buffer :: bitstring

  @typedoc "This is required to be valid UTF-8"
  @type utf8 :: binary

  @type frame :: :ping | :pong | :close | {:ping, binary} | {:pong, binary} |
                 {:close, close_code, utf8} | {:text, utf8} | {:binary, binary} |
                 {:fragment, :text | :binary, binary} | {:continuation, binary} |
                 {:fin, binary}

  defdelegate parse_frame(frame), to: WebSockex.Frame.Parser
  defdelegate parse_fragment(fragment, continuaion), to: WebSockex.Frame.Parser

  def encode_frame(:ping) do
    mask = create_mask()
    {:ok, <<1::1, 0::3, 9::4, 1::1, 0::7, mask::bytes-size(4)>>}
  end
  def encode_frame({:ping, <<payload::binary>>}) when byte_size(payload) > 125 do
    {:error, %WebSockex.FrameEncodeError{reason: :control_frame_too_large,
                                         frame_type: :ping,
                                         frame_payload: payload}} 
  end

  def create_mask do
    :crypto.strong_rand_bytes(4)
  end
end
