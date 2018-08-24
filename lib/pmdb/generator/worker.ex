defmodule Pmdb.Generator.Worker do
  def parse_path_and_do(path_str, action) do
    result = Pmdb.Path.parse(path_str)

    case result do
      {:ok, path} ->
        action.(path)

      error ->
        error
    end
  end

  def handle_cast_base(path_str, action) do
    result =
      parse_path_and_do(path_str, fn path ->
        :mnesia.transaction(fn ->
          action.(path)
        end)
      end)

    case result do
      {:atomic, value} -> value
      {:aborted, error} -> {:error, error}
    end

    {:noreply, nil}
  end

  defmacro generate_cast_handler_without_args(method) do
    quote do
      def handle_cast({unquote(method), path_str}, _) do
        Pmdb.Generator.Worker.handle_cast_base(path_str, fn path -> unquote(method)(path) end)
      end
    end
  end

  defmacro generate_cast_handler_with_one_arg(method) do
    quote do
      def handle_cast({unquote(method), path_str, arg}, _) do
        Pmdb.Generator.Worker.handle_cast_base(path_str, fn path -> unquote(method)(path, arg) end)
      end
    end
  end
end
