defmodule Pmdb.Generator.Worker do
  defp handle_cast_base(path_str, action) do
    path_result = Pmdb.Path.parse(path_str)

    result =
      case path_result do
        {:ok, path} ->
          :mnesia.transaction(fn ->
            action.(path)
          end)

        _ ->
          nil
      end

    case result do
      {:atomic, value} -> value
      {:aborted, error} -> {:error, error}
      _ -> nil
    end

    {:noreply, nil}
  end

  defmacro generate_cast_handler_without_args(method) do
    quote do
      def handle_cast({unquote(method), path_str}, _) do
        handle_cast_base(path_str, fn path -> unquote(method)(path) end)
      end
    end
  end

  defmacro generate_cast_handler_with_one_arg(method) do
    quote do
      def handle_cast({unquote(method), path_str, arg}, _) do
        handle_cast_base(path_str, fn path -> unquote(method)(path, arg) end)
      end
    end
  end
end
