defprotocol Pmdb.Handler do
  @spec get(path :: String.t()) :: {:ok, Schema.data()} | {:error, String.t()}
  def get(path)
  @spec post(path :: String.t(), value :: Schema.data()) :: :ok | {:error, String.t()}
  def post(path, value)
  @spec put(path :: String.t(), value :: Schema.data()) :: :ok | {:error, String.t()}
  def put(path, value)
  @spec delete(path :: String.t()) :: :ok | {:error, String.t()}
  def delete(path)
  @spec patch(path :: String.t(), delta :: Schema.data_delta()) :: :ok | {:error, String.t()}
  def patch(path, delta)

  @spec describe(path :: String.t()) :: {:ok, Schema.data_type()} | {:error, String.t()}
  def describe(path)
  @spec validate(path :: String.t(), schema :: Schema.data_type()) ::
              :ok | {:error, String.t()}
  def validate(path, schema)
end
