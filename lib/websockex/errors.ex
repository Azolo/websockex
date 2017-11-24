defmodule WebSockex.ApplicationError do
  @moduledoc false
  defexception [:reason]

  def message(%__MODULE__{reason: :not_started}) do
    """
    The :websockex application is not started.
    Please start the applications with Application.ensure_all_started(:websockex)
    """
  end
end

defmodule WebSockex.ConnError do
  @moduledoc false
  defexception [:original]

  def message(%__MODULE__{original: :nxdomain}), do: "Connection Error: Could not resolve domain name."
  def message(%__MODULE__{original: error}), do: "Connection Error: #{inspect error}"
end

defmodule WebSockex.RequestError do
  defexception [:code, :message]

  def message(%__MODULE__{code: code, message: message}) do
    "Didn't get a proper response from the server. The response was: #{inspect code} #{inspect message}"
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
     "Response: #{inspect response}",
     "Challenge: #{inspect challenge}"]
    |> Enum.join("\n")
  end
end

defmodule WebSockex.BadResponseError do
  @moduledoc false
  defexception [:response, :module, :function, :args]

  def message(%__MODULE__{} = error) do
    "Bad Response: Got #{inspect error.response} from #{inspect Exception.format_mfa(error.module, error.function, error.args)}"
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
  defexception [:reason, :frame_type, :frame_payload, :close_code]

  def message(%__MODULE__{reason: :control_frame_too_large} = error) do
    """
    Control frame payload too large: Payload must be less than 126 bytes.
    Frame: {#{inspect error.frame_type}, #{inspect error.frame_payload}}
    """
  end
  def message(%__MODULE__{reason: :close_code_out_of_range} = error) do
    """
    Close Code Out of Range: Close code must be between 1000-4999.
    Frame: {#{inspect error.frame_type}, #{inspect error.close_code}, #{inspect error.frame_payload}}
    """
  end
end

defmodule WebSockex.InvalidFrameError do
  defexception [:frame]

  def message(%__MODULE__{frame: frame}) do
    "The following frame is an invalid frame: #{inspect frame}"
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

defmodule WebSockex.NotConnectedError do
  defexception [:connection_state]

  def message(%__MODULE__{connection_state: :opening}) do
    "Not Connected: Currently Opening the Connection."
  end
end

defmodule WebSockex.CallingSelfError do
  defexception [:function]

  def message(%__MODULE__{function: :send_frame}) do
    """
    Process attempted to call itself.

    The function send_frame/2 cannot be used inside of a callback. Instead try returning {:reply, frame, state} from the callback.
    """
  end
  def message(%__MODULE__{}) do
    "Process attempted to call itself."
  end
end
