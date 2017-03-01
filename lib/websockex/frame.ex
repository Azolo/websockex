defmodule WebSockex.Frame do
  @moduledoc """
  Functions for parsing and encoding frames.
  """

  @data_codes %{text: 1,
                binary: 2}

  @control_codes %{close: 8,
                   ping: 9,
                   pong: 10}

  @opcodes Map.merge(@data_codes, @control_codes)

  @type opcode :: :text | :binary | :close | :ping | :pong
  @type buffer :: bitstring

  defstruct [:opcode, :payload]

  @type t :: %__MODULE__{opcode: opcode,
                         payload: binary | nil}

  @doc """
  Parses a bitstring and returns a frame.
  """
  @spec parse_frame(bitstring) ::
    {:incomplete, buffer} | {__MODULE__.t, buffer} | {:error, %WebSockex.FrameError{}}
  def parse_frame(data) when bit_size(data) < 16 do
    {:incomplete, data}
  end
  for {key, opcode} <- @control_codes do
    def parse_frame(<<1::1, 0::3, unquote(opcode)::4, 0::1, 0::7, buffer::bitstring>>) do
      {%__MODULE__{opcode: unquote(key)}, buffer}
    end
    def parse_frame(<<0::1, 0::3, unquote(opcode)::4, 0::1, len::7, _::bitstring>>) do
      {:error,
        %WebSockex.FrameError{reason: :nonfin_control_frame,
                              opcode: unquote(key),
                              fin: 0,
                              length: len,
                              mask: 0}}
    end
  end

  for {key, opcode} <- @opcodes do
    def parse_frame(<<1::1, 0::3, unquote(opcode)::4, 0::1, len::7, rest::bitstring>>) do
      <<payload::bytes-size(len), buffer::bitstring>> = rest
      {%__MODULE__{opcode: unquote(key), payload: payload}, buffer}
    end
  end
end
