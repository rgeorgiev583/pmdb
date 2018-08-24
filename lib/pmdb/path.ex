defmodule Pmdb.Path do
  defp get_path_matching_environment() do
    path_separator = Application.get_env(:pmdb, :path_separator)
    path_index_opening_delimiter = Application.get_env(:pmdb, :path_index_opening_delimiter)
    path_index_closing_delimiter = Application.get_env(:pmdb, :path_index_closing_delimiter)

    {path_separator, path_index_opening_delimiter, path_index_closing_delimiter}
  end

  defp get_path_list_from_string(path_str, path_separator, index_expr_regex) do
    path_str
    |> String.split(path_separator)
    |> Enum.map(fn component ->
      index_expr_match = Regex.run(index_expr_regex, component)

      case index_expr_match do
        [_, list_name, list_index] -> [list_name, String.to_integer(list_index)]
        _ -> [component]
      end
    end)
    |> Enum.concat()
  end

  def parse(path_str) do
    {path_separator, path_index_opening_delimiter, path_index_closing_delimiter} =
      get_path_matching_environment()

    index_expr_regex_result =
      Regex.compile(
        "^([^" <>
          Regex.escape(path_index_opening_delimiter) <>
          Regex.escape(path_index_closing_delimiter) <>
          "]*)" <>
          Regex.escape(path_index_opening_delimiter) <>
          "(\\d+)" <> Regex.escape(path_index_closing_delimiter) <> "$"
      )

    case index_expr_regex_result do
      {:ok, index_expr_regex} ->
        {:ok, get_path_list_from_string(path_str, path_separator, index_expr_regex)}

      error ->
        error
    end
  end

  def to_string(path) do
    {path_separator, path_index_opening_delimiter, path_index_closing_delimiter} =
      get_path_matching_environment()

    path
    |> Enum.reduce(fn component, path_str ->
      cond do
        is_integer(component) ->
          path_str <>
            path_index_opening_delimiter <>
            Integer.to_string(component) <> path_index_closing_delimiter

        true ->
          path_str <> path_separator <> component
      end
    end)
  end

  def get_pattern(path) do
    List.foldr(path, :_, fn component, base -> [component | base] end)
  end
end
