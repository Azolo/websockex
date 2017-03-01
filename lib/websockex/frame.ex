defmodule WebSockex.Frame do
  @moduledoc """
  Functions for parsing and encoding frames.
  """

  @type ping_frame :: :ping | {:ping, binary}

  @type frame :: ping_frame

  @doc """
  Parses a bitstring and returns a frame.
  """
  @spec parse_frame(bitstring) :: {:incomplete, bitstring} | frame
  def parse_frame(data) when bit_size(data) < 16 do
    {:incomplete, data}
  end
end
