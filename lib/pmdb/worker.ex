defmodule Pmdb.Worker do
  use GenServer

  # Client API

  def start_link(options) do
    GenServer.start_link(__MODULE__, :ok, [name: __MODULE__] ++ options)
  end

  # Helper functions

  defp do_with_appropriate_handler([], _) do
    {:error, "handler not found for the provided path"}
  end

  defp do_with_appropriate_handler(matching_handler_list, action) do
    {relative_path, handler} =
      Enum.max_by(matching_handler_list, fn {relative_path, _} -> length(relative_path) end)

    relative_path_str = Pmdb.Path.to_string(relative_path)
    action.(handler, relative_path_str)
  end

  defp do_with_handler(path, action) do
    match_handlers = fn {handler_path, handler}, matching_handler_list ->
      matching_handler_entry =
        case path do
          [^handler_path | _] ->
            relative_path = path |> Enum.drop(length(handler_path))
            [{relative_path, handler}]

          _ ->
            []
        end

      matching_handler_list ++ matching_handler_entry
    end

    matching_handler_list =
      :mnesia.foldl(
        match_handlers,
        [],
        :handlers
      )

    do_with_appropriate_handler(matching_handler_list, action)
  end

  defp construct_list_object(path) do
    match_spec = [{{path ++ [:"$1"], :"$2"}, [is_integer: :"$1"], [{{:"$1", :"$2"}}]}]

    :mnesia.select(:data, match_spec)
    |> Enum.sort_by(fn {index, _} -> index end)
    |> Enum.map(fn {index, value} -> construct_data_object(path ++ [index], value) end)
  end

  defp construct_map_object(path) do
    match_spec = [{{path ++ [:"$1"], :"$2"}, [is_binary: :"$1"], [{{:"$1", :"$2"}}]}]

    :mnesia.select(:data, match_spec)
    |> Enum.map(fn {key, value} -> construct_data_object(path ++ [key], value) end)
    |> Map.new()
  end

  defp construct_data_object(path, :list) do
    construct_list_object(path)
  end

  defp construct_data_object(path, :map) do
    construct_map_object(path)
  end

  defp construct_data_object(_, value) do
    value
  end

  defp deconstruct_list_object(path, list) do
    list
    |> Enum.with_index()
    |> Enum.map(fn {value, index} -> deconstruct_object(path ++ [index], value) end)

    :list
  end

  defp deconstruct_map_object(path, map) do
    map |> Enum.map(fn {key, value} -> deconstruct_object(path ++ [key], value) end)
    :map
  end

  defp deconstruct_data_object(path, object) when is_list(object) do
    deconstruct_list_object(path, object)
  end

  defp deconstruct_data_object(path, object) when is_map(object) do
    deconstruct_map_object(path, object)
  end

  defp deconstruct_data_object(_, object) do
    object
  end

  defp deconstruct_object(path, object) do
    value = deconstruct_data_object(path, object)
    :mnesia.write({:data, path, value})
    value
  end

  defp get_list_object_last_index(path) do
    match_spec = [{{path ++ [:"$1"], :"$2"}, [is_integer: :"$1"], [{{:"$1", :"$2"}}]}]
    :mnesia.select(:data, match_spec) |> Enum.max_by(fn {index, _} -> index end, fn -> -1 end)
  end

  defp get(path, :handle, [{path, value}], _) do
    object = construct_data_object(path, value)
    {:ok, object}
  end

  defp get(path, :handle, _, get_from_handler) do
    do_with_handler(path, get_from_handler)
  end

  defp get(path, cache_mode) when cache_mode != :upstream do
    data = :mnesia.read(:data, path)

    get(path, :handle, data, fn handler, relative_path_str ->
      result = Pmdb.Handler.get(handler, relative_path_str)

      case result do
        {:ok, value} ->
          put(path, value)
          result

        error ->
          error
      end
    end)
  end

  defp get(path, _) do
    data = :mnesia.read(:data, path)

    get(path, :handle, data, fn handler, relative_path_str ->
      Pmdb.Handler.get(handler, relative_path_str)
    end)
  end

  defp post(path, object, 1) do
    next_index = get_list_object_last_index(path) + 1
    entry_path = path ++ [next_index]
    deconstruct_object(entry_path, object)
    :ok
  end

  defp post(_, _, _) do
    {:error, "the post/2 call only supports lists as the target objects"}
  end

  defp post(path, value) do
    data = :mnesia.match_object({:data, path, :list})
    post(path, value, length(data))
  end

  defp put(path, object, :ok) do
    deconstruct_object(path, object)
    :ok
  end

  defp put(_, _, error) do
    error
  end

  defp put(path, value) do
    result = delete(path)
    put(path, value, result)
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

  defp shift_list_entries(_, _, _) do
    {:error, "object is not a list entry"}
  end

  defp shift_list_entries(path, shifter) do
    index = List.last(path)
    shift_list_entries(path, shifter, index)
  end

  defp delete(path) do
    pattern = Pmdb.Path.get_pattern(path)

    :mnesia.match_object({:data, pattern, :_})
    |> Enum.map(fn entry -> :mnesia.delete_object(entry) end)

    shift_list_entries(path, &shift_left/2)
  end

  defp patch_list(entry_path, data, :ok) do
    put(entry_path, data)
  end

  defp patch_list(_, _, error) do
    error
  end

  defp patch_list(path, {:replace, index, entry_delta}) do
    patch(path ++ [index], entry_delta)
  end

  defp patch_list(path, {:insert, index, data}) do
    entry_path = path ++ [index]
    result = shift_list_entries(entry_path, &shift_right/2)
    patch_list(entry_path, data, result)
  end

  defp patch(_, nil) do
    :ok
  end

  defp patch(path, :drop) do
    delete(path)
  end

  defp patch(path, {:data, data}) do
    put(path, data)
  end

  defp patch(path, {:list, list_delta_list}) do
    list_delta_list
    |> Enum.map(fn list_delta -> patch_list(path, list_delta) end)
    |> Pmdb.Utility.reduce_results()
  end

  defp patch(path, {:map, delta_map}) do
    delta_map
    |> Enum.map(fn {key, entry_delta} -> patch(path ++ [key], entry_delta) end)
    |> Pmdb.Utility.reduce_results()
  end

  defp flush(path, use_cache, cache_mode)
       when use_cache == true and cache_mode != :downstream do
    pattern = Pmdb.Path.get_pattern(path)

    :mnesia.match_object({:handlers, pattern, :_})
    |> Enum.map(fn {handler_path, handler} ->
      handler_pattern = Pmdb.Path.get_pattern(handler_path)

      data =
        :mnesia.match_object({:data, handler_pattern, :_})
        |> Enum.map(fn {path, value} ->
          relative_path = path |> Enum.drop(length(handler_path))
          {relative_path, value}
        end)

      delta = {:map, data |> Map.new()}
      root = Application.get_env(:pmdb, :path_root)
      Pmdb.Handler.patch(handler, root, delta)
    end)
    |> Pmdb.Utility.reduce_results()
  end

  defp flush(_, _, _) do
    {:error, "upstream caching is disabled"}
  end

  defp clear(path, use_cache, _)
       when use_cache == true do
    pattern = Pmdb.Path.get_pattern(path)

    :mnesia.match_object({:handlers, pattern, :_})
    |> Enum.map(fn {handler_path, _} ->
      handler_pattern = Pmdb.Path.get_pattern(handler_path)

      :mnesia.match_object({:data, handler_pattern, :_})
      |> Enum.map(fn {path, _} -> :mnesia.delete({:data, path}) end)
    end)

    :ok
  end

  defp clear(_, _, _) do
    {:error, "caching is disabled"}
  end

  defp attach(path, handler) do
    :mnesia.write({:handlers, path, handler})
  end

  defp detach(path) do
    :mnesia.delete({:handlers, path})
  end

  import Pmdb.Generator.Worker

  defp get(path, use_cache, cache_mode) when use_cache == true do
    get(path, cache_mode)
  end

  defp get(path, _, _) do
    do_with_handler(path, fn handler, relative_path_str ->
      Pmdb.Handler.get(handler, relative_path_str)
    end)
  end

  generate_cache_aware_handler_implementation_with_one_arg(:post)
  generate_cache_aware_handler_implementation_with_one_arg(:put)
  generate_cache_aware_handler_implementation_without_args(:delete)
  generate_cache_aware_handler_implementation_with_one_arg(:patch)

  # Server API

  def init(:ok) do
    {:ok, nil}
  end

  def handle_transaction_result({:atomic, value}) do
    value
  end

  def handle_transaction_result({:aborted, error}) do
    {:error, error}
  end

  def handle_call({:get, path_str}, _, _) do
    result =
      Pmdb.Path.parse_path_and_do(path_str, fn path ->
        :mnesia.transaction(fn ->
          use_cache = Application.get_env(:pmdb, :use_cache)
          cache_mode = Application.get_env(:pmdb, :cache_mode)
          get(path, use_cache, cache_mode)
        end)
      end)

    reply = handle_transaction_result(result)
    {:reply, reply, nil}
  end

  generate_cache_aware_call_handler_with_one_arg(:post)
  generate_cache_aware_call_handler_with_one_arg(:put)
  generate_cache_aware_call_handler_without_args(:delete)
  generate_cache_aware_call_handler_with_one_arg(:patch)
  generate_cache_aware_call_handler_without_args(:flush)
  generate_cache_aware_call_handler_without_args(:clear)
  generate_call_handler_with_one_arg(:attach)
  generate_call_handler_without_args(:detach)

  generate_cache_aware_cast_handler_with_one_arg(:post)
  generate_cache_aware_cast_handler_with_one_arg(:put)
  generate_cache_aware_cast_handler_without_args(:delete)
  generate_cache_aware_cast_handler_with_one_arg(:patch)
  generate_cache_aware_cast_handler_without_args(:flush)
  generate_cache_aware_cast_handler_without_args(:clear)
  generate_cast_handler_with_one_arg(:attach)
  generate_cast_handler_without_args(:detach)
end
