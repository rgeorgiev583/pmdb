defmodule Pmdb.Worker do
  use GenServer

  # Client API

  def start_link(options) do
    GenServer.start_link(__MODULE__, :ok, [name: __MODULE__] ++ options)
  end

  # Helper functions

  defp get_from_handler(path) do
    traverse_handlers = fn {handler_path, handler}, matching_handler_list ->
      matching_handler =
        case path do
          [^handler_path | _] -> [{path, handler}]
          _ -> []
        end

      matching_handler_list ++ matching_handler
    end

    matching_handler_list =
      :ets.foldl(
        traverse_handlers,
        [],
        :handlers
      )

    case matching_handler_list do
      [] ->
        {:error, "handler not found for the provided path"}

      list ->
        most_appropriate_handler_entry = Enum.max_by(list, fn {path, _} -> length(path) end)
        {entry_path, entry_handler} = most_appropriate_handler_entry
        entry_path_str = Pmdb.Path.list2str(entry_path)
        Pmdb.Handler.get(entry_handler, entry_path_str)
    end
  end

  defp construct_list_object(path) do
    match_spec = [{{path ++ [:"$1"], :"$2"}, [is_integer: :"$1"], [{{:"$1", :"$2"}}]}]

    :ets.select(:data, match_spec)
    |> Enum.sort_by(fn {index, _} -> index end)
    |> Enum.map(fn {index, value} -> construct_data_object(path ++ [index], value) end)
  end

  defp construct_map_object(path) do
    match_spec = [{{path ++ [:"$1"], :"$2"}, [is_binary: :"$1"], [{{:"$1", :"$2"}}]}]

    :ets.select(:data, match_spec)
    |> Enum.map(fn {key, value} -> construct_data_object(path ++ [key], value) end)
    |> Map.new()
  end

  defp construct_data_object(path, value) do
    case value do
      :list -> construct_list_object(path)
      :map -> construct_map_object(path)
      value -> value
    end
  end

  defp deconstruct_list_object(path, value) do
    value
    |> Enum.with_index()
    |> Enum.map(fn {element, index} -> deconstruct_data_object(path ++ [index], element) end)

    :list
  end

  defp deconstruct_map_object(path, value) do
    value |> Enum.map(fn {key, element} -> deconstruct_data_object(path ++ [key], element) end)
    :map
  end

  defp deconstruct_data_object(path, value) do
    internal_value =
      cond do
        is_list(value) -> deconstruct_list_object(path, value)
        is_map(value) -> deconstruct_map_object(path, value)
        true -> value
      end

    :ets.insert(:data, {path, internal_value})
    internal_value
  end

  defp get_list_object_last_index(path) do
    match_spec = [{{path ++ [:"$1"], :"$2"}, [is_integer: :"$1"], [{{:"$1", :"$2"}}]}]
    :ets.select(:data, match_spec) |> Enum.max_by(fn {index, _} -> index end, fn -> -1 end)
  end

  defp get(path) do
    values = :ets.lookup(:data, path)

    case values do
      [{^path, value}] -> {:ok, construct_data_object(path, value)}
      _ -> get_from_handler(path)
    end
  end

  defp put(path, value) do
    delete(path)
    deconstruct_data_object(path, value)
    :ok
  end

  defp post(path, value) do
    values = :ets.match_object(:data, {path, :list})

    case length(values) do
      1 ->
        next_index = get_list_object_last_index(path) + 1
        element_path = path ++ [next_index]
        deconstruct_data_object(element_path, value)
        :ok

      _ ->
        {:error, "the post/2 call only supports lists as the target objects"}
    end
  end

  defp shift_left(path_without_index, data) do
    max_index = data |> Enum.max_by(fn {index, _} -> index end, fn -> -1 end)

    data
    |> Enum.sort_by(fn {index, _} -> index end)
    |> Enum.map(fn {index, value} ->
      :ets.insert(:data, {path_without_index ++ [index - 1], value})
    end)

    :ets.delete(:data, path_without_index ++ [max_index])
  end

  defp shift_right(path_without_index, data) do
    data
    |> Enum.sort_by(fn {index, _} -> index end, &Kernel.>=/2)
    |> Enum.map(fn {index, value} ->
      :ets.insert(:data, {path_without_index ++ [index + 1], value})
    end)

    :ok
  end

  defp shift_list_elements(path, shifter) do
    index = List.last(path)

    cond do
      is_integer(index) ->
        {_, path_without_index} = List.pop_at(path, -1)

        match_spec = [
          {{path_without_index ++ [:"$1"], :"$2"},
           [{:andalso, {:is_integer, :"$1"}, {:>, :"$1", index}}], [{{:"$1", :"$2"}}]}
        ]

        data = :ets.select(:data, match_spec)
        shifter.(path_without_index, data)

      true ->
        {:error, "object is not a list element"}
    end
  end

  defp delete(path) do
    pattern = Pmdb.Path.list2pattern(path)
    :ets.match_delete(:data, {pattern, :_})
    shift_list_elements(path, &shift_left/2)
  end

  defp patch_list(path, list_delta) do
    case list_delta do
      {:replace, index, element_delta} ->
        patch(path ++ [index], element_delta)

      {:insert, index, data} ->
        element_path = path ++ [index]
        shift_list_elements(element_path, &shift_right/2)
        put(element_path, data)
    end
  end

  defp patch(path, delta) do
    case delta do
      nil ->
        :ok

      :drop ->
        delete(path)

      {:data, data} ->
        put(path, data)

      {:list, list_delta_list} ->
        list_delta_list
        |> Enum.map(fn list_delta -> patch_list(path, list_delta) end)

      {:map, delta_map} ->
        delta_map |> Enum.map(fn {key, element_delta} -> patch(path ++ [key], element_delta) end)
    end

    :ok
  end

  defp flush(path) do
    pattern = Pmdb.Path.list2pattern(path)

    errors =
      :ets.match_object(:handlers, {pattern, :_})
      |> Enum.map(fn {path, handler} ->
        data = :ets.match_object(:data, {path, :_})
        delta = {:map, Map.new(data)}
        Pmdb.Handler.patch(handler, path, delta)
      end)
      |> Enum.filter(fn result ->
        case result do
          {:error, _} -> true
          _ -> false
        end
      end)
      |> Enum.map(fn {:error, error} -> error end)

    case errors do
      [] -> :ok
      errors -> {:error, errors |> Enum.join("\n")}
    end
  end

  defp attach(path, handler) do
    :ets.insert(:handlers, {path, handler})
  end

  defp detach(path) do
    :ets.delete(:handlers, path)
  end

  # Server API

  import Pmdb.Generator.Worker

  def init(:ok) do
    {:ok, nil}
  end

  def handle_call({:get, path_str}, _, _) do
    path = Pmdb.Path.str2list(path_str)
    value = get(path)
    reply = {:ok, value}
    {:reply, reply, nil}
  end

  generate_cast_handler_with_one_arg(:post)
  generate_cast_handler_with_one_arg(:put)
  generate_cast_handler_without_args(:delete)
  generate_cast_handler_with_one_arg(:patch)
  generate_cast_handler_without_args(:flush)
  generate_cast_handler_with_one_arg(:attach)
  generate_cast_handler_without_args(:detach)
end
