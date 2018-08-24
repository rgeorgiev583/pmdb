defmodule Pmdb.Generator.Worker do
  defmacro generate_cast_handler_without_args(method) do
    quote do
      def handle_cast({unquote(method), path_str}, _) do
        path_result = Pmdb.Path.parse(path_str)

        case path_result do
          {:ok, path} -> unquote(method)(path)
          _ -> nil
        end

        {:noreply, nil}
      end
    end
  end

  defmacro generate_cast_handler_with_one_arg(method) do
    quote do
      def handle_cast({unquote(method), path_str, arg}, _) do
        path_result = Pmdb.Path.parse(path_str)

        case path_result do
          {:ok, path} -> unquote(method)(path, arg)
          _ -> nil
        end

        {:noreply, nil}
      end
    end
  end
end
