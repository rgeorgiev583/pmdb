defmodule Pmdb.Worker do
  use GenServer

  # Client API

  def start_link(options) do
    GenServer.start_link(__MODULE__, :ok, [name: __MODULE__] ++ options)
  end

  # Helper functions

  defp retrieve_from_appropriate_handler([]) do
    {:error, "handler not found for the provided path"}
  end

  defp retrieve_from_appropriate_handler(matching_handler_list) do
    {relative_path, handler} =
      Enum.max_by(matching_handler_list, fn {relative_path, _} -> length(relative_path) end)

    relative_path_str = Pmdb.Path.to_string(relative_path)
    Pmdb.Handler.get(handler, relative_path_str)
  end

  defp get_from_handler(path) do
    match_handlers = fn {handler_path, handler}, matching_handler_list ->
      matching_handler_entry =
        case path do
          [^handler_path | _] ->
            relative_path = Enum.drop(path, length(handler_path))
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

    retrieve_from_appropriate_handler(matching_handler_list)
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

  defp get(path, [{path, value}]) do
    object = construct_data_object(path, value)
    {:ok, object}
  end

  defp get(path, _) do
    get_from_handler(path)
  end

  defp get(path) do
    data = :mnesia.read(:data, path)
    get(path, data)
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

  defp shift_left(path_without_index, data) do
    max_index = data |> Enum.max_by(fn {index, _} -> index end, fn -> -1 end)

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
    {_, path_without_index} = List.pop_at(path, -1)

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

  defp reduce_errors([]) do
    :ok
  end

  defp reduce_errors(errors) do
    {:error, errors |> Enum.join("\n")}
  end

  defp reduce_results(results) do
    errors =
      results
      |> Enum.filter(fn result ->
        case result do
          {:error, _} -> true
          _ -> false
        end
      end)
      |> Enum.map(fn {:error, error} -> error end)

    reduce_errors(errors)
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
    |> reduce_results()
  end

  defp patch(path, {:map, delta_map}) do
    delta_map
    |> Enum.map(fn {key, entry_delta} -> patch(path ++ [key], entry_delta) end)
    |> reduce_results()
  end

  defp flush(path) do
    pattern = Pmdb.Path.get_pattern(path)

    :mnesia.match_object({:handlers, pattern, :_})
    |> Enum.map(fn {handler_path, handler} ->
      handler_pattern = Pmdb.Path.get_pattern(handler_path)

      data =
        :mnesia.match_object({:data, handler_pattern, :_})
        |> Enum.map(fn {path, value} ->
          relative_path = Enum.drop(path, length(handler_path))
          {relative_path, value}
        end)

      delta = {:map, Map.new(data)}
      Pmdb.Handler.patch(handler, "", delta)
    end)
    |> reduce_results()
  end

  defp attach(path, handler) do
    :mnesia.write({:handlers, path, handler})
  end

  defp detach(path) do
    :mnesia.delete({:handlers, path})
  end

  defp clear(path) do
    pattern = Pmdb.Path.get_pattern(path)

    :mnesia.match_object({:handlers, pattern, :_})
    |> Enum.map(fn {handler_path, _} ->
      handler_pattern = Pmdb.Path.get_pattern(handler_path)

      :mnesia.match_object({:data, handler_pattern, :_})
      |> Enum.map(fn {path, _} -> :mnesia.delete({:data, path}) end)
    end)

    :ok
  end

  # Server API

  import Pmdb.Generator.Worker

  def init(:ok) do
    {:ok, nil}
  end

  def handle_call({:get, path_str}, _, _) do
    reply = Pmdb.Generator.Worker.parse_path_and_do(path_str, fn path -> get(path) end)
    {:reply, reply, nil}
  end

  generate_cast_handler_with_one_arg(:post)
  generate_cast_handler_with_one_arg(:put)
  generate_cast_handler_without_args(:delete)
  generate_cast_handler_with_one_arg(:patch)
  generate_cast_handler_without_args(:flush)
  generate_cast_handler_with_one_arg(:attach)
  generate_cast_handler_without_args(:detach)
  generate_cast_handler_without_args(:clear)
end
