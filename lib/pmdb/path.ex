defmodule Pmdb.Path do
  def str2list(path_str) do
    path_separator = Application.get_env(:pmdb, :path_separator)

    path_str
    |> String.split(path_separator)
    |> Enum.map(fn component ->
      index_spec_match = Regex.run(~r/^([^\[\]]*)\[(\d+)\]$/, component)

      case index_spec_match do
        [_, list_name, list_index] -> [list_name, String.to_integer(list_index)]
        _ -> [component]
      end
    end)
    |> Enum.concat()
  end

  def list2str(path) do
    path_separator = Application.get_env(:pmdb, :path_separator)

    path
    |> Enum.reduce(fn component, path_str ->
      cond do
        is_integer(component) -> path_str <> "[" <> Integer.to_string(component) <> "]"
        true -> path_str <> path_separator <> component
      end
    end)
  end

  def list2pattern(path) do
    List.foldr(path, :_, fn component, base -> [component | base] end)
  end
end
