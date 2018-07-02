defmodule Pmdb.Schema do
  @type primitive_data() :: boolean() | number() | binary() | bitstring()
  @type primitive_data_type() :: :boolean | :integer | :float | :binary | :bitstring | :string
  @type data() ::
          primitive_data()
          | [data()]
          | %{required(String.t()) => data()}
  @type data_type() ::
          primitive_data_type()
          | {:list, [data_type()]}
          | {:list, %{required(String.t()) => data_type()}}
end
