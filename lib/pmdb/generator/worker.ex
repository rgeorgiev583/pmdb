defmodule Pmdb.Generator.Worker do
  defmacro generate_cast_handler_without_args(method) do
    quote do
      def handle_cast({unquote(method), path_str}, _) do
        path = Pmdb.Path.str2list(path_str)
        unquote(method)(path)
        {:noreply, nil}
      end
    end
  end

  defmacro generate_cast_handler_with_one_arg(method) do
    quote do
      def handle_cast({unquote(method), path_str, arg}, _) do
        path = Pmdb.Path.str2list(path_str)
        unquote(method)(path, arg)
        {:noreply, nil}
      end
    end
  end
end
