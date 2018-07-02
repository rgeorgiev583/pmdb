defmodule Pmdb.Schema do
  @type primitive_data() :: boolean() | number() | binary() | bitstring()
  @type primitive_data_type() :: :boolean | :integer | :float | :binary | :bitstring | :string
  @type annotated_primitive_data() ::
          {:boolean, boolean()}
          | {:integer, integer()}
          | {:float, float()}
          | {:binary, binary()}
          | {:bitstring, bitstring()}
          | {:string, String.t()}
  @type data() ::
          primitive_data()
          | [data()]
          | %{required(String.t()) => data()}
  @type data_type() ::
          primitive_data_type()
          | {:list, [data_type()]}
          | {:map, %{required(String.t()) => data_type()}}
  @type annotated_data() ::
          annotated_primitive_data()
          | {:list, [annotated_data()]}
          | {:map, %{required(String.t()) => annotated_data()}}
end
