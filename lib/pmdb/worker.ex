defmodule Pmdb.Worker do
  use GenServer

  ## Client API

  def start_link(options) do
    GenServer.start_link(__MODULE__, :ok, [name: __MODULE__] ++ options)
  end

  def init(:ok) do
    {:ok, nil}
  end

  # Server API

  defp path_str2list(path_str) do
    String.split(path_str, ".")
  end

  defp path_list2str(path) do
    Enum.join(path, ".")
  end

  defp path_list2pattern(path) do
    List.foldr(path, :_, fn component, base -> [component | base] end)
  end

  def handle_cast({:attach, path_str, handler}, _) do
    path = path_str2list(path_str)
    :mnesia.transaction(fn -> :mnesia.write({:handlers, path, handler}) end)
    {:noreply, nil}
  end

  def handle_cast({:detach, path_str}, _) do
    path = path_str2list(path_str)
    :mnesia.transaction(fn -> :mnesia.delete({:handlers, path}) end)
    {:noreply, nil}
  end

  defp get_from_handler(path) do
    result =
      :mnesia.transaction(fn ->
        traverse_handlers = fn {handler_path, handler}, handler_list ->
          handlers =
            case path do
              [^handler_path | _] -> [handler]
              _ -> []
            end

          handler_list ++ handlers
        end

        handler_list =
          :mnesia.foldl(
            traverse_handlers,
            [],
            :handlers
          )

        case handler_list do
          [handler] ->
            path_str = path_list2str(path)
            {:ok, Pmdb.Handler.get(path_str)}

          _ ->
            {:error, "handler not found for the provided path"}
        end
      end)

    case result do
      {:atomic, value} -> value
      {:aborted, error} -> {:error, error}
      _ -> nil
    end
  end

  defp construct_list_object(path) do
    result =
      :mnesia.transaction(fn ->
        match_spec = [{{path ++ [:"$1"], :"$2"}, [is_integer: :"$1"], [{{:"$1", :"$2"}}]}]

        :mnesia.select(:data, match_spec)
        |> Enum.sort_by(fn {index, _} -> index end)
        |> Enum.map(fn {index, value} -> construct_data_object(path ++ [index], value) end)
      end)

    case result do
      {:atomic, value} -> value
      {:aborted, error} -> {:error, error}
      _ -> nil
    end
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

  def get(path) do
    values = :ets.lookup(:data, path)

    case values do
      [{^path, value}] -> {:ok, construct_data_object(path, value)}
      _ -> get_from_handler(path)
    end
  end

  def put(path, value) do
    delete(path)
    deconstruct_data_object(path, value)
    :ok
  end

  def post(path, value) do
    values = :ets.match_object(:data, {path, :list})

    case length(values) do
      1 ->
        next_index = get_list_object_last_index(path) + 1
        element_path = path ++ [next_index]
        deconstruct_data_object(element_path, value)
        :ets.insert(:updates, {path, :post})
        :ok

      _ ->
        {:error, "the post/2 call only supports lists as the target objects"}
    end
  end

  def delete(path) do
    pattern = path_list2pattern(path)
    :ets.match_delete(:data, {pattern, :_})
    :ets.insert(:updates, {path, :delete})
    :ok
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
  end

  defp shift_list_elements(path, shifter) do
    index = List.last(path)

    case index do
      is_integer(index) ->
        path_without_index = List.pop_at(path, -1)

        match_spec = [
          {{path_without_index ++ [:"$1"], :"$2"},
           [{:andalso, {:is_integer, :"$1"}, {:>, :"$1", index}}], [{{:"$1", :"$2"}}]}
        ]

        data = :ets.select(:data, match_spec)
        shifter.(path_without_index, data)
        :ok

      _ ->
        {:error, "object is not a list element"}
    end
  end

  def patch_list(path, list_delta) do
    case list_delta do
      {:replace, index, element_delta} ->
        patch(path ++ [index], element_delta)

      {:insert, index, data} ->
        element_path = path ++ [index]
        shift_list_elements(element_path, &shift_right/2)
        put(element_path, data)
    end
  end

  def patch(path, delta) do
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
  end

  def handle_call({:get, path_str}, _, _) do
    path = path_str2list(path_str)
    {:reply, get(path), nil}
  end

  def handle_cast({:post, path_str, value}, _) do
    path = path_str2list(path_str)
    post(path, value)
    {:noreply, nil}
  end

  def handle_cast({:put, path_str, value}, _) do
    path = path_str2list(path_str)
    put(path, value)
    {:noreply, nil}
  end

  def handle_cast({:delete, path_str}, _) do
    path = path_str2list(path_str)
    delete(path)
    shift_list_elements(path, &shift_left/2)
    {:noreply, nil}
  end

  def handle_cast({:patch, path_str, delta}, _) do
    path = path_str2list(path_str)
    patch(path, delta)
    {:noreply, nil}
  end

  def handle_cast({:flush, path_str}, _) do
    path = path_str2list(path_str)
  end
end
