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

  @opcodes %{text: 1,
             binary: 2,
             close: 8,
             ping: 9,
             pong: 10}

  @doc """
  Encodes a frame into a binary for sending.
  """
  @spec encode_frame(frame) :: {:ok, binary} | {:error, %WebSockex.FrameEncodeError{}}
  def encode_frame(frame)
  # Encode Ping and Pong Frames
  for {key, opcode} <- Map.take(@opcodes, [:ping, :pong]) do
    def encode_frame({unquote(key), <<payload::binary>>}) when byte_size(payload) > 125 do
      {:error,
        %WebSockex.FrameEncodeError{reason: :control_frame_too_large,
                                    frame_type: unquote(key),
                                    frame_payload: payload}}
    end
    def encode_frame(unquote(key)) do
      mask = create_mask_key()
      {:ok, <<1::1, 0::3, unquote(opcode)::4, 1::1, 0::7, mask::bytes-size(4)>>}
    end
    def encode_frame({unquote(key), <<payload::binary>>}) do
      mask = create_mask_key()
      len = byte_size(payload)
      masked_payload = mask(mask, payload)
      {:ok, <<1::1, 0::3, unquote(opcode)::4, 1::1, len::7, mask::bytes-size(4), masked_payload::binary-size(len)>>}
    end
  end
  # Encode Close Frames
  def encode_frame({:close, close_code, <<payload::binary>>})
  when not close_code in 1000..4999 do
    {:error,
      %WebSockex.FrameEncodeError{reason: :close_code_out_of_range,
                                  frame_type: :close,
                                  frame_payload: payload,
                                  close_code: close_code}}
  end
  def encode_frame({:close, close_code, <<payload::binary>>})
  when byte_size(payload) > 123 do
    {:error,
      %WebSockex.FrameEncodeError{reason: :control_frame_too_large,
                                  frame_type: :close,
                                  frame_payload: payload,
                                  close_code: close_code}}
  end
  def encode_frame(:close) do
    mask = create_mask_key()
    {:ok, <<1::1, 0::3, 8::4, 1::1, 0::7, mask::bytes-size(4)>>}
  end
  def encode_frame({:close, close_code, <<payload::binary>>}) do
    mask = create_mask_key()
    payload = <<close_code::16, payload::binary>>
    len = byte_size(payload)
    masked_payload = mask(mask, payload)
    {:ok, <<1::1, 0::3, 8::4, 1::1, len::7, mask::bytes-size(4), masked_payload::binary>>}
  end
  # Encode Text and Binary frames
  for {key, opcode} <- Map.take(@opcodes, [:text, :binary]) do
    def encode_frame({unquote(key), payload}) do
      mask = create_mask_key()
      {payload_len_bin, payload_len_size} = get_payload_length_bin(payload)
      masked_payload = mask(mask, payload)
      {:ok, <<1::1, 0::3, unquote(opcode)::4, 1::1, payload_len_bin::bits-size(payload_len_size), mask::bytes-size(4), masked_payload::binary>>}
    end
    # Start Fragments!
    def encode_frame({:fragment, unquote(key), payload}) do
      mask = create_mask_key()
      {payload_len_bin, payload_len_size} = get_payload_length_bin(payload)
      masked_payload = mask(mask, payload)
      {:ok, <<0::1, 0::3, unquote(opcode)::4, 1::1, payload_len_bin::bits-size(payload_len_size), mask::bytes-size(4), masked_payload::binary>>}
    end
  end
  # Handle other Fragments
  for {key, fin_bit} <- [{:continuation, 0}, {:finish, 1}] do
    def encode_frame({unquote(key), payload}) do
      mask = create_mask_key()
      {payload_len_bin, payload_len_size} = get_payload_length_bin(payload)
      masked_payload = mask(mask, payload)
      {:ok, <<unquote(fin_bit)::1, 0::3, 0::4, 1::1, payload_len_bin::bits-size(payload_len_size), mask::bytes-size(4), masked_payload::binary>>}
    end
  end

  defp create_mask_key do
    :crypto.strong_rand_bytes(4)
  end

  defp get_payload_length_bin(payload) do
    case byte_size(payload) do
      size when size <= 125 -> {<<size::7>>, 7}
      size when size <= 0xFFFF -> {<<126::7, size::16>>, 16+7}
      size when size <= 0x7FFFFFFFFFFFFFFF -> {<<127::7, 0::1, size::63>>, 64+7}
      _ -> raise "WTF, Seriously? You're trying to send a payload larger than #{0x7FFFFFFFFFFFFFFF} bytes?"
    end
  end

  defp mask(key, payload, acc \\ <<>>)
  defp mask(_, <<>>, acc), do: acc
  for x <- 1..3 do
    defp mask(<<key::8*unquote(x), _::binary>>, <<part::8*unquote(x)>>, acc) do
      masked = part ^^^ key
      <<acc::binary, masked::8*unquote(x)>>
    end
  end
  defp mask(<<key::32>> = key_bin, <<part::8*4, rest::binary>>, acc) do
    masked = part ^^^ key
    mask(key_bin, rest, <<acc::binary, masked::8*4>>)
  end
end
