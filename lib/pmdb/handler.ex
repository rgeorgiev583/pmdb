defprotocol Pmdb.Handler do
  @spec get(context :: any, path :: String.t()) :: {:ok, Schema.data()} | {:error, String.t()}
  def get(context, path)

  @spec post(context :: any, path :: String.t(), value :: Schema.data()) ::
          :ok | {:error, String.t()}
  def post(context, path, value)

  @spec put(context :: any, path :: String.t(), value :: Schema.data()) ::
          :ok | {:error, String.t()}
  def put(context, path, value)

  @spec delete(context :: any, path :: String.t()) :: :ok | {:error, String.t()}
  def delete(context, path)

  @spec patch(context :: any, path :: String.t(), delta :: Schema.data_delta()) ::
          :ok | {:error, String.t()}
  def patch(context, path, delta)
end
