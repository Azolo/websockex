defmodule WebSockex.Frame do
  @moduledoc """
  Functions for parsing and encoding frames.
  """

  import Bitwise

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
  def encode_frame({:ping, <<payload::binary>>}) do
    mask = create_mask()
    len = byte_size(payload)
    masked_payload = mask(mask, payload)
    {:ok, <<1::1, 0::3, 9::4, 1::1, len::7, mask::bytes-size(4), masked_payload::binary-size(len)>>}
  end

  defp create_mask do
    :crypto.strong_rand_bytes(4)
  end

  defp mask(key, payload, acc \\ <<>>)
  defp mask(_, <<>>, acc), do: acc
  for x <- 1..3 do
    defp mask(<<key::8*unquote(x), _::binary>>, <<part::8*unquote(x)>>, acc) do
      masked = part ^^^ key
      <<acc::binary, masked::8*unquote(x)>>
    end
  end
  defp mask(<<key::8*4>>, <<part::8*4, rest::binary>>, acc) do
    masked = part ^^^ key
    mask(<<key>>, rest, <<acc::binary, masked::8*4>>)
  end
end
