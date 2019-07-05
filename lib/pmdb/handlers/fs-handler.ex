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

  defp parse_path_and_do(handler, path_str, action) do
    Pmdb.Path.parse_path_and_do(path_str, fn path ->
      fs_path = path |> Enum.map(&get_component_str/1) |> Path.join()
      abs_fs_path = Path.join(handler.root_path, fs_path)
      action.(abs_fs_path)
    end)
  end

  defp get_impl(path, {:type, :directory}, {:ok, entries}) do
    entries |> Map.new(fn key -> {key, get_impl(Path.join(path, key))} end)
  end

  defp get_impl(_, {:type, :regular}, {:ok, value}) do
    :erlang.binary_to_term(value)
  end

  defp get_impl(_, {:type, :directory}, error) do
    error
  end

  defp get_impl(_, {:type, :regular}, error) do
    error
  end

  defp get_impl(path, {:type, :directory}) do
    result = File.ls(path)
    get_impl(path, {:type, :directory}, result)
  end

  defp get_impl(path, {:type, :regular}) do
    result = File.read(path)
    get_impl(path, {:type, :regular}, result)
  end

  defp get_impl(_, {:type, _}) do
    {:error, "unsupported file type"}
  end

  defp get_impl(path, {:ok, info}) do
    get_impl(path, {:type, info.type})
  end

  defp get_impl(_, error) do
    error
  end

  defp get_impl(path) do
    file_stat = File.stat(path)
    get_impl(path, file_stat)
  end

  def get(handler, path_str) do
    parse_path_and_do(handler, path_str, fn path ->
      get_impl(path)
    end)
  end

  def post(_, _, _) do
    {:error, "not implemented"}
  end

  defp put_impl(path, list, :write) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.map(fn {value, index} ->
      put_impl(Path.join(path, Integer.to_string(index)), value, :put)
    end)
  end

  defp put_impl(path, map, :write) when is_map(map) do
    map |> Enum.map(fn {key, value} -> put_impl(Path.join(path, key), value, :put) end)
  end

  defp put_impl(path, value, :write) do
    data = :erlang.term_to_binary(value)
    File.write(path, data)
  end

  defp put_impl(path, value, :put) do
    dir_path = Path.basename(path)
    File.mkdir_p(dir_path)
    put_impl(path, value, :write)
  end

  defp put_impl(path, value, {:ok, _}) do
    File.rm_rf(path)
    put_impl(path, value, :put)
  end

  defp put_impl(path, value, _) do
    put_impl(path, value, :put)
  end

  defp put_impl(path, value) do
    file_stat = File.stat(path)
    put_impl(path, value, file_stat)
  end

  def put(handler, path_str, value) do
    parse_path_and_do(handler, path_str, fn path ->
      put_impl(path, value)
    end)
  end

  defp delete_impl(path) do
    File.rm_rf(path)
  end

  def delete(handler, path_str) do
    parse_path_and_do(handler, path_str, fn path ->
      delete_impl(path)
    end)
  end

  defp shift_left(_, []) do
    :ok
  end

  defp shift_left(path_without_index, data) do
    max_index = Enum.max_by(data, fn {index, _} -> index end, fn -> -1 end)

    data
    |> Enum.sort_by(fn {index, _} -> index end)
    |> Enum.map(fn {index, value} ->
      :mnesia.write({:data, path_without_index ++ [index - 1], value})
    end)

    :mnesia.delete({:data, path_without_index ++ [max_index]})
  end

  defp shift_right(_, []) do
    :ok
  end

  defp shift_right(path_without_index, data) do
    data
    |> Enum.sort_by(fn {index, _} -> index end, &Kernel.>=/2)
    |> Enum.map(fn {index, value} ->
      :mnesia.write({:data, path_without_index ++ [index + 1], value})
    end)

    :ok
  end

  defp shift_list_entries(path, shifter, index) when is_integer(index) do
    {_, path_without_index} = path |> List.pop_at(-1)

    match_spec = [
      {{path_without_index ++ [:"$1"], :"$2"},
       [{:andalso, {:is_integer, :"$1"}, {:>, :"$1", index}}], [{{:"$1", :"$2"}}]}
    ]

    data = :mnesia.select(:data, match_spec)
    shifter.(path_without_index, data)
  end

  defp shift_list_entries(path, shifter) do
    index = length(path) - 1
    shift_list_entries(path, shifter, index)
  end

  defp delete(path) do
    pattern = Pmdb.Path.get_pattern(path)

    :mnesia.match_object({:data, pattern, :_})
    |> Enum.map(fn entry -> :mnesia.delete_object(entry) end)

    shift_list_entries(path, &shift_left/2)
  end

  defp patch_list(entry_path, data, :ok) do
    put_impl(entry_path, data)
  end

  defp patch_list(path, {:modify, index, entry_delta}) do
    patch_impl(path ++ [index], entry_delta)
  end

  defp patch_list(path, {:insert, index, data}) do
    entry_path = path ++ [index]
    result = shift_list_entries(entry_path, &shift_right/2)
    patch_list(entry_path, data, result)
  end

  defp patch_list(path, {:append, data}) do
    last_index = get_list_object_last_index(path)
    entry_path = path ++ [last_index + 1]
    patch_list(entry_path, data, :ok)
  end

  defp patch_impl(_, nil) do
    :ok
  end

  defp patch_impl(path, :drop) do
    delete_impl(path)
  end

  defp patch_impl(path, {:data, data}) do
    put_impl(path, data)
  end

  defp patch_impl(path, {:list, list_delta_list}) do
    list_delta_list
    |> Enum.map(fn list_delta -> patch_list(path, list_delta) end)
    |> Pmdb.Utility.reduce_results()
  end

  defp patch_impl(path, {:map, delta_map}) do
    delta_map
    |> Enum.map(fn {key, entry_delta} -> patch_impl(Path.join(path, key), entry_delta) end)
    |> Pmdb.Utility.reduce_results()
  end

  def patch(handler, path_str, delta) do
    parse_path_and_do(handler, path_str, fn path ->
      patch_impl(path, delta)
    end)
  end
end
