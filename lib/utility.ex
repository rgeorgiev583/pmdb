defmodule Pmdb.Utility do
  defp reduce_errors([]) do
    :ok
  end

  defp reduce_errors(errors) do
    {:error, Enum.join(errors, "\n")}
  end

  def reduce_results(results) do
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
end
