defmodule WebSockex.ConnError do
  @moduledoc false
  defexception [:original]

  def message(%__MODULE__{original: :nxdomain}), do: "Connection Error: Could not resolve domain name."
  def message(%__MODULE__{original: error}), do: "Connection Error: #{inspect error}"
end

defmodule WebSockex.Conn.RequestError do
  defexception [:code, :message]

  def message(%__MODULE__{code: code, message: message}) do
    "Didn't get a proper response from the server. The response was: #{code} #{message}"
  end
end

defmodule WebSockex.URLError do
  @moduledoc false
  defexception [:url]

  def message(%__MODULE__{url: url}), do: "Invalid URL: #{inspect url}"
end

defmodule WebSockex.HandshakeError do
  @moduledoc false
  defexception [:challenge, :response]

  def message(%__MODULE__{challenge: challenge, response: response}) do
    ["Handshake Failed: Response didn't match challenge.",
     "Response: #{response}",
     "Challenge: #{challenge}"]
    |> Enum.join("\n")
  end
end

defmodule WebSockex.BadResponseError do
  @moduledoc false
  defexception [:response, :module, :function, :args]

  def message(%__MODULE__{} = error) do
    "Bad Response: Got #{error.response} from #{Exception.format_mfa(error.module, error.function, error.args)}"
  end
end

defmodule WebSockex.FrameError do
  defexception [:reason, :opcode, :buffer]

  def message(%__MODULE__{reason: :nonfin_control_frame} = exception) do
    "Fragmented Control Frame: Control Frames Can't Be Fragmented\nbuffer: #{exception.buffer}"
  end
  def message(%__MODULE__{reason: :control_frame_too_large} = exception) do
    "Control Frame Too Large: Control Frames Can't Be Larger Than 125 Bytes\nbuffer: #{exception.buffer}"
  end
  def message(%__MODULE__{reason: :invalid_utf8} = exception) do
    "Invalid UTF-8: Text and Close frames must have UTF-8 payloads.\nbuffer: #{exception.buffer}"
  end
  def message(%__MODULE__{reason: :invalid_close_code} = exception) do
    "Invalid Close Code: Close Codes must be in range of 1000 through 4999\nbuffer: #{exception.buffer}"
  end
  def message(%__MODULE__{} = exception) do
    "Frame Error: #{inspect exception}"
  end
end

defmodule WebSockex.FrameEncodeError do
  defexception [:reason, :frame_type, :frame_payload]

  def message(%__MODULE__{reason: :control_frame_too_large} = error) do
    """
    Control frame payload too large: Payload must be less than 126 bytes.
    Frame: {#{inspect error.frame_type}, #{inspect error.frame_payload}}
    """
  end
end

defmodule WebSockex.FragmentParseError do
  defexception [:reason, :fragment, :continuation]

  def message(%__MODULE__{reason: :two_start_frames} = error) do
    """
    Cannot Add Another Start Frame to a Existing Fragment.
    Fragment: #{inspect error.fragment}
    Continuation: #{inspect error.continuation}
    """
  end
end
