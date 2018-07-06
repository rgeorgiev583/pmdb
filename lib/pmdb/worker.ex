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

  defp path_list2pattern(path) do
    List.foldr(path, :_, fn component, base -> [component | base] end)
  end

  def handle_cast({:attach, path_str, handler}, _) do
    path = path_str2list(path_str)
    :ets.insert(:handlers, {path, handler})
    {:noreply, nil}
  end

  def handle_cast({:detach, path_str}, _) do
    path = path_str2list(path_str)
    :ets.delete(:handlers, path)
    {:noreply, nil}
  end

  defp get_from_handler(path, path_str) do
    traverse_handlers = fn {handler_path, handler}, handler_list ->
      handlers =
        case path do
          [^handler_path | _] -> [handler]
          _ -> []
        end

      handler_list ++ handlers
    end

    handler_list =
      :ets.foldl(
        traverse_handlers,
        [],
        :handlers
      )

    case handler_list do
      [handler] -> {:ok, Pmdb.Handler.get(path_str)}
      _ -> {:error, "handler not found for the provided path"}
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

  def get(path_str) do
    path = path_str2list(path_str)
    values = :ets.lookup(:data, path)

    case values do
      [{^path, value}] -> {:ok, construct_data_object(path, value)}
      _ -> get_from_handler(path, path_str)
    end
  end

  def put(path_str, value) do
    path = path_str2list(path_str)
    deconstruct_data_object(path, value)
    :ets.insert(:updates, {path})
    :ok
  end

  def handle_call({:get, path_str}, _, _) do
    {:reply, get(path_str), nil}
  end

  def handle_cast({:put, path_str, value}, _) do
    put(path_str, value)
    {:noreply, nil}
  end
end
