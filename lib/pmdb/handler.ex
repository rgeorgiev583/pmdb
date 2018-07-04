defmodule Pmdb.Handler do
  @callback get(path :: String.t()) :: {:ok, Schema.data()} | {:error, String.t()}
  @callback post(path :: String.t(), value :: Schema.data()) :: :ok | {:error, String.t()}
  @callback put(path :: String.t(), value :: Schema.data()) :: :ok | {:error, String.t()}
  @callback delete(path :: String.t()) :: :ok | {:error, String.t()}
  @callback patch(path :: String.t(), delta :: Schema.data_delta()) :: :ok | {:error, String.t()}

  @callback describe(path :: String.t()) :: {:ok, Schema.data_type()} | {:error, String.t()}
  @callback validate(path :: String.t(), schema :: Schema.data_type()) ::
              :ok | {:error, String.t()}
end
