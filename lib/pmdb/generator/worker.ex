defmodule Pmdb.Generator.Worker do
  def parse_path_and_do({:ok, path}, action) do
    action.(path)
  end

  def parse_path_and_do({:error, error}, _) do
    error
  end

  def parse_path_and_do(path_str, action) do
    result = Pmdb.Path.parse(path_str)
    parse_path_and_do(result, action)
  end

  def handle_cast_base(path_str, action) do
    parse_path_and_do(path_str, fn path ->
      :mnesia.transaction(fn ->
        action.(path)
      end)
    end)

    {:noreply, nil}
  end

  def handle_call_base({:atomic, _}) do
    :ok
  end

  def handle_call_base({:aborted, error}) do
    {:error, error}
  end

  def handle_call_base(path_str, action) do
    result =
      parse_path_and_do(path_str, fn path ->
        :mnesia.transaction(fn ->
          action.(path)
        end)
      end)

    reply = handle_call_base(result)
    {:reply, reply, nil}
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

  defmacro generate_call_handler_without_args(method) do
    quote do
      def handle_call({unquote(method), path_str}, _, _) do
        Pmdb.Generator.Worker.handle_call_base(path_str, fn path -> unquote(method)(path) end)
      end
    end
  end

  defmacro generate_call_handler_with_one_arg(method) do
    quote do
      def handle_call({unquote(method), path_str, arg}, _, _) do
        Pmdb.Generator.Worker.handle_call_base(path_str, fn path -> unquote(method)(path, arg) end)
      end
    end
  end
end
