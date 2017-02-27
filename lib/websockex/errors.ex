defmodule WebSockex.ConnError do
  @moduledoc false
  defexception [:error]

  # This seems subpar, maybe look at this later
  def message(%__MODULE__{error: error}), do: "Connection Error: #{inspect error}"
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
