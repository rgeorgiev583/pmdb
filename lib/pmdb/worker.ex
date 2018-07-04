defmodule Pmdb.Worker do
  use GenServer

  ## Client API

  def start_link(options) do
    GenServer.start_link(__MODULE__, :ok, [name: __MODULE__] ++ options)
  end

  def init(:ok) do
    {:ok}
  end

  # Server API

  defp path2list(path) do
    String.split(path, ".")
  end

  def handle_cast({:attach, path, handler}, _) do
    list = path2list(path)
    :ets.insert(:handlers, {list, handler})
    {:noreply}
  end
end
