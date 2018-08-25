defmodule Pmdb.Path do
  defp get_path_matching_environment() do
    path_separator = Application.get_env(:pmdb, :path_separator)
    path_index_opening_delimiter = Application.get_env(:pmdb, :path_index_opening_delimiter)
    path_index_closing_delimiter = Application.get_env(:pmdb, :path_index_closing_delimiter)

    {path_separator, path_index_opening_delimiter, path_index_closing_delimiter}
  end

  defp get_path_component_from_regex_match(_, [_, list_name, list_index]) do
    [list_name, String.to_integer(list_index)]
  end

  defp get_path_component_from_regex_match(component_str, _) do
    [component_str]
  end

  defp get_path_component_from_string(component_str, index_expr_regex) do
    index_expr_match = Regex.run(index_expr_regex, component_str)
    get_path_component_from_regex_match(component_str, index_expr_match)
  end

  defp get_path_list_from_string(path_str, path_separator, index_expr_regex) do
    path_str
    |> String.split(path_separator)
    |> Enum.map(fn component_str ->
      get_path_component_from_string(component_str, index_expr_regex)
    end)
    |> Enum.concat()
  end

  defp parse(path_str, path_separator, {:ok, index_expr_regex}) do
    {:ok, get_path_list_from_string(path_str, path_separator, index_expr_regex)}
  end

  defp parse(_, _, error) do
    error
  end

  defp parse_path_and_do(:do, {:ok, path}, action) do
    action.(path)
  end

  defp parse_path_and_do(:do, {:error, error}, _) do
    error
  end

  def parse_path_and_do(path_str, action) do
    result = parse(path_str)
    parse_path_and_do(:do, result, action)
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

    parse(path_str, path_separator, index_expr_regex_result)
  end

  def append_path_component(path_str, component) when is_integer(component) do
    {_, path_index_opening_delimiter, path_index_closing_delimiter} =
      get_path_matching_environment()

    path_str <>
      path_index_opening_delimiter <> Integer.to_string(component) <> path_index_closing_delimiter
  end

  def append_path_component(path_str, component) do
    {path_separator, _, _} = get_path_matching_environment()
    path_str <> path_separator <> component
  end

  def to_string(path) do
    path
    |> Enum.reduce(fn component, path_str -> append_path_component(path_str, component) end)
  end

  def get_pattern(path) do
    List.foldr(path, :_, fn component, base -> [component | base] end)
  end
end
