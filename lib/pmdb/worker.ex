defmodule Pmdb.Worker do
  use GenServer

  # Client API

  def start_link(options) do
    GenServer.start_link(__MODULE__, :ok, [name: __MODULE__] ++ options)
  end

  # Helper functions

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

    case matching_handler_list do
      [] ->
        {:error, "handler not found for the provided path"}

      list ->
        {relative_path, handler} =
          Enum.max_by(list, fn {relative_path, _} -> length(relative_path) end)

        relative_path_str = Pmdb.Path.to_string(relative_path)
        Pmdb.Handler.get(handler, relative_path_str)
    end
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

  defp deconstruct_list_object(path, value) do
    value
    |> Enum.with_index()
    |> Enum.map(fn {entry, index} -> deconstruct_object(path ++ [index], entry) end)

    :list
  end

  defp deconstruct_map_object(path, value) do
    value |> Enum.map(fn {key, entry} -> deconstruct_object(path ++ [key], entry) end)
    :map
  end

  defp deconstruct_data_object(path, value) when is_list(value) do
    deconstruct_list_object(path, value)
  end

  defp deconstruct_data_object(path, value) when is_map(value) do
    deconstruct_map_object(path, value)
  end

  defp deconstruct_data_object(_, value) do
    value
  end

  defp deconstruct_object(path, value) do
    internal_value = deconstruct_data_object(path, value)
    :mnesia.write({:data, path, internal_value})
    internal_value
  end

  defp get_list_object_last_index(path) do
    match_spec = [{{path ++ [:"$1"], :"$2"}, [is_integer: :"$1"], [{{:"$1", :"$2"}}]}]
    :mnesia.select(:data, match_spec) |> Enum.max_by(fn {index, _} -> index end, fn -> -1 end)
  end

  defp get(path) do
    values = :mnesia.read(:data, path)

    case values do
      [{^path, value}] -> {:ok, construct_data_object(path, value)}
      _ -> get_from_handler(path)
    end
  end

  defp put(path, value) do
    result = delete(path)

    case result do
      :ok ->
        deconstruct_object(path, value)
        :ok

      error ->
        error
    end
  end

  defp post(path, value) do
    values = :mnesia.match_object({:data, path, :list})

    case length(values) do
      1 ->
        next_index = get_list_object_last_index(path) + 1
        entry_path = path ++ [next_index]
        deconstruct_object(entry_path, value)
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

  defp shift_list_entries(path, shifter) do
    index = List.last(path)

    cond do
      is_integer(index) ->
        {_, path_without_index} = List.pop_at(path, -1)

        match_spec = [
          {{path_without_index ++ [:"$1"], :"$2"},
           [{:andalso, {:is_integer, :"$1"}, {:>, :"$1", index}}], [{{:"$1", :"$2"}}]}
        ]

        data = :mnesia.select(:data, match_spec)
        shifter.(path_without_index, data)

      true ->
        {:error, "object is not a list entry"}
    end
  end

  defp delete(path) do
    pattern = Pmdb.Path.get_pattern(path)

    :mnesia.match_object({:data, pattern, :_})
    |> Enum.map(fn value -> :mnesia.delete_object(value) end)

    shift_list_entries(path, &shift_left/2)
  end

  defp patch_list(path, list_delta) do
    case list_delta do
      {:replace, index, entry_delta} ->
        patch(path ++ [index], entry_delta)

      {:insert, index, data} ->
        entry_path = path ++ [index]
        result = shift_list_entries(entry_path, &shift_right/2)

        case result do
          :ok ->
            put(entry_path, data)

          error ->
            error
        end
    end
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

    case errors do
      [] -> :ok
      errors -> {:error, errors |> Enum.join("\n")}
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
        |> reduce_results()

      {:map, delta_map} ->
        delta_map
        |> Enum.map(fn {key, entry_delta} -> patch(path ++ [key], entry_delta) end)
        |> reduce_results()
    end
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
    path_result = Pmdb.Path.parse(path_str)

    reply =
      case path_result do
        {:ok, path} -> {:ok, get(path)}
        error -> error
      end

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
