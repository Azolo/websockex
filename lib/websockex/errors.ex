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
  defexception [:reason, :fin, :opcode, :mask, :length, :payload]

  def message(%__MODULE__{reason: :nonfin_control_frame, fin: 0} = exception) do
    "Control Frames Can't Be Fragmented: opcode: #{exception.opcode}, fin: #{exception.fin}"
  end
  def message(%__MODULE__{} = exception) do
    "Frame Error: #{inspect exception}"
  end
end
