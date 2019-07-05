defmodule Pmdb.FileSystemHandler do
  defstruct root_path: Path.absname("")

  def init(path) do
    %__MODULE__{root_path: path}
  end
end

defimpl Pmdb.Handler, for: Pmdb.FileHandler do
  defp get_component_str(component) when is_integer(component) do
    Integer.to_string(component)
  end

  defp get_component_str(component) do
    component
  end

  defp convert_path_to_fs_path(handler, path) do
    fs_path = path |> Enum.map(&get_component_str/1) |> Path.join()
    Path.join(handler.root_path, fs_path)
  end

  defp get_impl(handler, path, {:type, :directory}, {:ok, entries}) do
    entries |> Map.new(fn key -> {key, get_impl(handler, path ++ [key])} end)
  end

  defp get_impl(_, _, {:type, :regular}, {:ok, value}) do
    :erlang.binary_to_term(value)
  end

  defp get_impl(_, _, {:type, :directory}, error) do
    error
  end

  defp get_impl(_, _, {:type, :regular}, error) do
    error
  end

  defp get_impl(handler, path, {:type, :directory}) do
    fs_path = convert_path_to_fs_path(handler, path)
    result = File.ls(fs_path)
    get_impl(handler, path, {:type, :directory}, result)
  end

  defp get_impl(handler, path, {:type, :regular}) do
    fs_path = convert_path_to_fs_path(handler, path)
    result = File.read(fs_path)
    get_impl(handler, path, {:type, :regular}, result)
  end

  defp get_impl(_, _, {:type, _}) do
    {:error, "unsupported file type"}
  end

  defp get_impl(handler, path, {:ok, info}) do
    get_impl(handler, path, {:type, info.type})
  end

  defp get_impl(_, _, error) do
    error
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
