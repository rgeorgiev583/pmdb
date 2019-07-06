defmodule Pmdb.FileSystemHandler do
  defstruct root_path: Path.absname("")

  def init(path) do
    %__MODULE__{root_path: path}
  end
end

defimpl Pmdb.Handler, for: Pmdb.FileHandler do
  defp append_component(fs_path, component) when is_integer(component) do
    list_fs_path = fs_path <> ".list"
    index = Integer.to_string(component)
    Path.join(list_fs_path, index)
  end

  defp append_component(fs_path, component) do
    map_fs_path = fs_path <> ".map"
    Path.join(map_fs_path, component)
  end

  defp convert_path_to_fs_path(handler, path) do
    path |> Enum.reduce(handler.root_path, &append_component/2)
  end

  defp get_path_with_extension(path, extension) do
    basename = path |> List.last()
    list_basename = basename <> "." <> extension
    path |> List.replace_at(-1, list_basename)
  end

  defp get_list_path(path) do
    get_path_with_extension(path, "list")
  end

  defp get_map_path(path) do
    get_path_with_extension(path, "map")
  end

  defp get_impl(handler, path, {:type, :directory, :map}, {:ok, entries}) do
    entries |> Map.new(fn key -> {key, get_impl(handler, path ++ [key])} end)
  end

  defp get_impl(handler, path, {:type, :directory, :list}, {:ok, entries}) do
    entries
    |> Map.new(fn key -> {key, get_impl(handler, path ++ [key])} end)
    |> Enum.map(&String.to_integer/1)
    |> Enum.sort_by(fn {index, _} -> index end)
    |> Enum.map(fn {index, value} -> construct_data_object(path ++ [index], value) end)
  end

  defp get_impl(_, _, {:type, :regular, :primitive}, {:ok, value}) do
    :erlang.binary_to_term(value)
  end

  defp get_impl(handler, path, {:type, :directory, :map}, {:error, :enotdir}) do
    list_path = get_list_path(path)
    fs_path = convert_path_to_fs_path(handler, list_path)
    result = File.ls(fs_path)
    get_impl(handler, path, {:type, :directory, :list}, result)
  end

  defp get_impl(_, _, {:type, :directory, _}, error) do
    error
  end

  defp get_impl(_, _, {:type, :regular, _}, error) do
    error
  end

  defp get_impl(handler, path, {:type, :directory}) do
    map_path = get_map_path(path)
    fs_path = convert_path_to_fs_path(handler, map_path)
    result = File.ls(fs_path)
    get_impl(handler, path, {:type, :directory, :map}, result)
  end

  defp get_impl(handler, path, {:type, :regular}) do
    fs_path = convert_path_to_fs_path(handler, path)
    result = File.read(fs_path)
    get_impl(handler, path, {:type, :regular, :primitive}, result)
  end

  defp get_impl(_, _, {:type, _}) do
    {:error, "unsupported file type"}
  end

  defp get_impl(handler, path, {:ok, info}) do
    get_impl(handler, path, {:type, info.type})
  end

  defp get_impl(handler, path) do
    fs_path = convert_path_to_fs_path(handler, path)
    file_stat = File.stat(fs_path)
    get_impl(handler, path, file_stat)
  end

  def get(handler, path_str) do
    Pmdb.Path.parse_path_and_do(path_str, fn path ->
      get_impl(handler, path)
    end)
  end

  def post(_, _, _) do
    {:error, "not implemented"}
  end

  defp put_impl(handler, path, list, :write) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.map(fn {value, index} ->
      put_impl(handler, path ++ [index], value, :put)
    end)
    |> Pmdb.Utility.reduce_results()
  end

  defp put_impl(handler, path, map, :write) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> put_impl(handler, path ++ [key], value, :put) end)
    |> Pmdb.Utility.reduce_results()
  end

  defp put_impl(handler, path, value, :write) do
    fs_path = convert_path_to_fs_path(handler, path)
    data = :erlang.term_to_binary(value)
    File.write(fs_path, data)
  end

  defp put_impl(handler, path, value, :put) do
    {_, dir_path} = path |> List.pop_at(-1)
    dir_fs_path = convert_path_to_fs_path(handler, dir_path)
    File.mkdir_p(dir_fs_path)
    put_impl(handler, path, value, :write)
  end

  defp put_impl(handler, path, value, {:ok, _}) do
    fs_path = convert_path_to_fs_path(handler, path)
    File.rm_rf(fs_path)
    put_impl(handler, path, value, :put)
  end

  defp put_impl(handler, path, value, _) do
    put_impl(handler, path, value, :put)
  end

  defp put_impl(handler, path, value) do
    fs_path = convert_path_to_fs_path(handler, path)
    file_stat = File.stat(fs_path)
    put_impl(handler, path, value, file_stat)
  end

  def put(handler, path_str, value) do
    Pmdb.Path.parse_path_and_do(path_str, fn path ->
      put_impl(handler, path, value)
    end)
  end

  defp delete_impl(handler, path) do
    fs_path = convert_path_to_fs_path(handler, path)
    File.rm_rf(fs_path)
  end

  def delete(handler, path_str) do
    Pmdb.Path.parse_path_and_do(path_str, fn path ->
      delete_impl(handler, path)
    end)
  end

  defp patch_impl(_, _, nil) do
    :ok
  end

  defp patch_impl(handler, path, :drop) do
    delete_impl(handler, path)
  end

  defp patch_impl(handler, path, {:data, data}) do
    put_impl(handler, path, data)
  end

  defp patch_impl(_, _, {:list, _}) do
    {:error, "not implemented"}
  end

  defp patch_impl(handler, path, {:map, delta_map}) do
    delta_map
    |> Enum.map(fn {key, entry_delta} -> patch_impl(handler, path ++ [key], entry_delta) end)
    |> Pmdb.Utility.reduce_results()
  end

  def patch(handler, path_str, delta) do
    Pmdb.Path.parse_path_and_do(path_str, fn path ->
      patch_impl(handler, path, delta)
    end)
  end
end
