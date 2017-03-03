defmodule WebSockex.Frame do
  @moduledoc """
  Functions for parsing and encoding frames.
  """

  @opcodes %{text: 1,
             binary: 2,
             close: 8,
             ping: 9,
             pong: 10}

  @type opcode :: :text | :binary | :close | :ping | :pong
  @type close_code :: 1000..4999

  @typedoc "The incomplete or unhandled remainder of a binary"
  @type buffer :: bitstring

  @typedoc "This is required to be valid UTF-8"
  @type utf8 :: binary

  @type frame :: :ping | :pong | :close | {:ping, binary} | {:pong, binary} |
                 {:close, close_code, utf8} | {:text, utf8} | {:binary, binary}

  @doc """
  Parses a bitstring and returns a frame.
  """
  @spec parse_frame(bitstring) ::
    :incomplete | {:ok, frame, buffer} | {:error, %WebSockex.FrameError{}}
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

  # Check for UTF-8 in Text payloads
  def parse_frame(<<1::1, 0::3, 1::4, 0::1, len::7, remaining::bitstring>> = buffer) do
    <<payload::bytes-size(len), rest::bitstring>> = remaining
    if String.valid?(payload) do
      {:ok, {:text, payload}, rest}
    else
      {:error, %WebSockex.FrameError{reason: :invalid_utf8,
                                     opcode: :text,
                                     buffer: buffer}}
    end
  end

  # Don't need to check for proper UTF-8 here
  for {key, opcode} <- Map.take(@opcodes, [:binary, :ping, :pong]) do
    def parse_frame(<<1::1, 0::3, unquote(opcode)::4, 0::1, len::7, remaining::bitstring>>) do
      <<payload::bytes-size(len), rest::bitstring>> = remaining
      {:ok, {unquote(key), payload}, rest}
    end
  end
end
