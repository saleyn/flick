defmodule Flick.Test.EchoSocket do
  @moduledoc false
  @behaviour WebSock

  @greeting %{type: :greeting, message: "hello from server", values: [1, 2, 3]}

  @impl WebSock
  def init(%{test_pid: test_pid}) do
    send(self(), :send_greeting)
    {:ok, %{test_pid: test_pid}}
  end

  @impl WebSock
  def handle_in({payload, [opcode: :binary]}, state) do
    decoded = :erlang.binary_to_term(payload)
    send(state.test_pid, {:echo, decoded})
    {:ok, state}
  end

  @impl WebSock
  def handle_info(:send_greeting, state) do
    {:push, {:binary, :erlang.term_to_binary(@greeting)}, state}
  end

  def handle_info(_msg, state), do: {:ok, state}

  @impl WebSock
  def terminate(_reason, _state), do: :ok
end
