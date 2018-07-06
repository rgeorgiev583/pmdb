defmodule Pmdb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      # Starts a worker by calling: Pmdb.Worker.start_link(arg)
      # {Pmdb.Worker, arg},
    ]

    :ets.new(:data, [:named_table, :public])
    :ets.new(:handlers, [:named_table, :public, read_concurrency: true])
    :ets.new(:updates, [:named_table, :public, write_concurrency: true])

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Pmdb.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
