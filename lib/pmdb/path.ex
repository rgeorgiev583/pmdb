defmodule Pmdb.Path do
  def str2list(path_str) do
    path_separator = Application.get_env(:pmdb, :path_separator)
    String.split(path_str, path_separator)
  end

  def list2str(path) do
    path_separator = Application.get_env(:pmdb, :path_separator)
    Enum.join(path, path_separator)
  end

  def list2pattern(path) do
    List.foldr(path, :_, fn (component, base) -> [component | base] end)
  end
end
