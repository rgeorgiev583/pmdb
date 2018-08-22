defmodule Pmdb.FileHandler do
  defstruct root_path

  def init(path) do
    %__MODULE__{root_path: path}
  end
end

defimpl Pmdb.Handler, for: Pmdb.FileHandler do
  def get(handler, path) do
    case File.stat(Path.join(handler.root_path, path)) do
      {:ok, info} ->
        case info.type do
          :directory -> File.ls(path) |> Map.new(fn key -> {key, get(handler, path ++ [key])} end)
          :regular -> File.read(path) |> :erlang.term_to_binary()
        end

      error ->
        error
    end
  end

  def post(handler, path) do
    case File.stat(Path.join()) do
      {:ok, info}
    end
  end
end
