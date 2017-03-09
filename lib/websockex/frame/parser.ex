defmodule WebSockex.Frame.Parser do
  alias WebSockex.{Frame}

  @opcodes %{text: 1,
             binary: 2,
             close: 8,
             ping: 9,
             pong: 10}

  @doc """
  Parses a bitstring and returns a frame.
  """
  @spec parse_frame(bitstring) ::
    :incomplete | {:ok, Frame.frame, Frame.buffer} | {:error, %WebSockex.FrameError{}}
  def parse_frame(data) when bit_size(data) < 16 do
    :incomplete
  end
  for {key, opcode} <- Map.take(@opcodes, [:close, :ping, :pong]) do
    # Control Codes can have 0 length payloads
    def parse_frame(<<1::1, 0::3, unquote(opcode)::4, 0::1, 0::7, buffer::bitstring>>) do
      {:ok, unquote(key), buffer}
    end
    # Large Control Frames
    def parse_frame(<<1::1, 0::3, unquote(opcode)::4, 0::1, 126::7, _::bitstring>> = buffer) do
      {:error, %WebSockex.FrameError{reason: :control_frame_too_large,
                                     opcode: unquote(key),
                                     buffer: buffer}}
    end
    def parse_frame(<<1::1, 0::3, unquote(opcode)::4, 0::1, 127::7, _::bitstring>> = buffer) do
      {:error, %WebSockex.FrameError{reason: :control_frame_too_large,
                                     opcode: unquote(key),
                                     buffer: buffer}}
    end
    # Nonfin Control Frames
    def parse_frame(<<0::1, 0::3, unquote(opcode)::4, 0::1, _::7, _::bitstring>> = buffer) do
      {:error, %WebSockex.FrameError{reason: :nonfin_control_frame,
                                     opcode: unquote(key),
                                     buffer: buffer}}
    end
  end

  # Incomplete Frames
  def parse_frame(<<_::9, len::7, remaining::bitstring>>) when byte_size(remaining) < len do
    :incomplete
  end
  for {_key, opcode} <- Map.take(@opcodes, [:text, :binary]) do
    def parse_frame(<<_::1, 0::3, unquote(opcode)::4, 0::1, 126::7, len::16, remaining::bitstring>>)
    when byte_size(remaining) < len do
      :incomplete
    end
    def parse_frame(<<_::1, 0::3, unquote(opcode)::4, 0::1, 127::7, len::64, remaining::bitstring>>)
    when byte_size(remaining) < len do
      :incomplete
    end
  end


  # Close Frame with Single Byte
  def parse_frame(<<1::1, 0::3, 8::4, 0::1, 1::7, _::bitstring>> = buffer) do
    {:error, %WebSockex.FrameError{reason: :close_with_single_byte_payload,
                                   opcode: :close,
                                   buffer: buffer}}
  end

  # Parse Close Frames with Payloads
  def parse_frame(<<1::1, 0::3, 8::4, 0::1, len::7, close_code::integer-size(16), remaining::bitstring>> = buffer)
  when close_code in 1000..4999 do
    size = len - 2
    <<payload::bytes-size(size), rest::bitstring>> = remaining
    if String.valid?(payload) do
      {:ok, {:close, close_code, payload}, rest}
    else
      {:error, %WebSockex.FrameError{reason: :invalid_utf8,
                                     opcode: :close,
                                     buffer: buffer}}
    end
  end
  def parse_frame(<<1::1, 0::3, 8::4, _::bitstring>> = buffer) do
    {:error, %WebSockex.FrameError{reason: :invalid_close_code,
                                   opcode: :close,
                                   buffer: buffer}}
  end

  # Ping and Pong with Payloads
  for {key, opcode} <- Map.take(@opcodes, [:ping, :pong]) do
    def parse_frame(<<1::1, 0::3, unquote(opcode)::4, 0::1, len::7, remaining::bitstring>>) do
      <<payload::bytes-size(len), rest::bitstring>> = remaining
      {:ok, {unquote(key), payload}, rest}
    end
  end

  # Text Frames (Check Valid UTF-8 Payloads)
  def parse_frame(<<1::1, 0::3, 1::4, 0::1, 126::7, len::16, remaining::bitstring>> = buffer) do
    parse_text_payload(len, remaining, buffer)
  end
  def parse_frame(<<1::1, 0::3, 1::4, 0::1, 127::7, len::64, remaining::bitstring>> = buffer) do
    parse_text_payload(len, remaining, buffer)
  end
  def parse_frame(<<1::1, 0::3, 1::4, 0::1, len::7, remaining::bitstring>> = buffer) do
    parse_text_payload(len, remaining, buffer)
  end

  # Binary Frames
  def parse_frame(<<1::1, 0::3, 2::4, 0::1, 126::7, len::16, remaining::bitstring>>) do
    <<payload::bytes-size(len), rest::bitstring>> = remaining
    {:ok, {:binary, payload}, rest}
  end
  def parse_frame(<<1::1, 0::3, 2::4, 0::1, 127::7, len::64, remaining::bitstring>>) do
    <<payload::bytes-size(len), rest::bitstring>> = remaining
    {:ok, {:binary, payload}, rest}
  end
  def parse_frame(<<1::1, 0::3, 2::4, 0::1, len::7, remaining::bitstring>>) do
    <<payload::bytes-size(len), rest::bitstring>> = remaining
    {:ok, {:binary, payload}, rest}
  end

  # Start of Fragmented Message
  for {key, opcode} <- Map.take(@opcodes, [:text, :binary]) do
    def parse_frame(<<0::1, 0::3, unquote(opcode)::4, 0::1, 126::7, len::16, remaining::bitstring>>) do
      <<payload::bytes-size(len), rest::bitstring>> = remaining
      {:ok, {:fragment, unquote(key), payload}, rest}
    end
    def parse_frame(<<0::1, 0::3, unquote(opcode)::4, 0::1, 127::7, len::64, remaining::bitstring>>) do
      <<payload::bytes-size(len), rest::bitstring>> = remaining
      {:ok, {:fragment, unquote(key), payload}, rest}
    end
    def parse_frame(<<0::1, 0::3, unquote(opcode)::4, 0::1, len::7, remaining::bitstring>>) do
      <<payload::bytes-size(len), rest::bitstring>> = remaining
      {:ok, {:fragment, unquote(key), payload}, rest}
    end
  end

  # Parse Fragmentation Continuation Frames
  def parse_frame(<<0::1, 0::3, 0::4, 0::1, 126::7, len::16, remaining::bitstring>>) do
    <<payload::bytes-size(len), rest::bitstring>> = remaining
    {:ok, {:continuation, payload}, rest}
  end
  def parse_frame(<<0::1, 0::3, 0::4, 0::1, 127::7, len::64, remaining::bitstring>>) do
    <<payload::bytes-size(len), rest::bitstring>> = remaining
    {:ok, {:continuation, payload}, rest}
  end
  def parse_frame(<<0::1, 0::3, 0::4, 0::1, len::7, remaining::bitstring>>) do
    <<payload::bytes-size(len), rest::bitstring>> = remaining
    {:ok, {:continuation, payload}, rest}
  end

  # Parse Fragmentation Finish Frames
  def parse_frame(<<1::1, 0::3, 0::4, 0::1, 126::7, len::16, remaining::bitstring>>) do
    <<payload::bytes-size(len), rest::bitstring>> = remaining
    {:ok, {:finish, payload}, rest}
  end
  def parse_frame(<<1::1, 0::3, 0::4, 0::1, 127::7, len::64, remaining::bitstring>>) do
    <<payload::bytes-size(len), rest::bitstring>> = remaining
    {:ok, {:finish, payload}, rest}
  end
  def parse_frame(<<1::1, 0::3, 0::4, 0::1, len::7, remaining::bitstring>>) do
    <<payload::bytes-size(len), rest::bitstring>> = remaining
    {:ok, {:finish, payload}, rest}
  end

  @doc """
  Parses and combines two frames in a fragmented segment.
  """
  @spec parse_fragment({:fragment, :text | :binary, binary},
                       {:continuation | :finish, binary}) ::
    {:fragment, :text | :binary, binary} | {:text | :binary, binary} |
    {:error, %WebSockex.FragmentParseError{}}
  def parse_fragment({:fragment, _, _} = frame0, {:fragment, _, _} = frame1) do
    {:error,
      %WebSockex.FragmentParseError{reason: :two_start_frames,
                                    fragment: frame0,
                                    continuation: frame1}}
  end
  def parse_fragment({:fragment, type, fragment}, {:continuation, continuation}) do
    {:ok, {:fragment, type, <<fragment::binary, continuation::binary>>}}
  end
  def parse_fragment({:fragment, :binary, fragment}, {:finish, continuation}) do
    {:ok, {:binary, <<fragment::binary, continuation::binary>>}}
  end
  # Make sure text is valid UTF-8
  def parse_fragment({:fragment, :text, fragment}, {:finish, continuation}) do
    text = <<fragment::binary, continuation::binary>>
    if String.valid?(text) do
      {:ok, {:text, text}}
    else
      {:error,
        %WebSockex.FrameError{reason: :invalid_utf8,
                              opcode: :text,
                              buffer: text}}
    end
  end

  defp parse_text_payload(len, remaining, buffer) do
    <<payload::bytes-size(len), rest::bitstring>> = remaining
    if String.valid?(payload) do
      {:ok, {:text, payload}, rest}
    else
      {:error, %WebSockex.FrameError{reason: :invalid_utf8,
                                     opcode: :text,
                                     buffer: buffer}}
    end
  end
end
