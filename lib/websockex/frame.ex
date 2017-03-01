defmodule WebSockex.Frame do
  @moduledoc """
  Functions for parsing and encoding frames.
  """

  @type opcode :: :ping

  defstruct [:opcode, :payload]

  @type t :: %__MODULE__{opcode: opcode,
                         payload: binary}

  @doc """
  Parses a bitstring and returns a frame.
  """
  @spec parse_frame(bitstring) :: {:incomplete, bitstring} | __MODULE__.t
  def parse_frame(data) when bit_size(data) < 16 do
    {:incomplete, data}
  end
  def parse_frame(<<1::1, 0::3, 9::4, 0::1, 0::7, buffer::bitstring>>) do
    {%__MODULE__{opcode: :ping}, buffer}
  end
  def parse_frame(<<1::1, 0::3, 9::4, 0::1, len::7, rest::bitstring>>) do
    <<payload::bytes-size(len), buffer::bitstring>> = rest
    {%__MODULE__{opcode: :ping, payload: payload}, buffer}
  end
end
