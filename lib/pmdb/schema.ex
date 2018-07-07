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
          | {:list, data_type()}
          | {:list, [data_type()]}
          | {:map, data_type()}
          | {:map, %{required(String.t()) => data_type()}}
  @type annotated_data() ::
          annotated_primitive_data()
          | {:list, [annotated_data()]}
          | {:map, %{required(String.t()) => annotated_data()}}

  @type list_delta() ::
          {:replace, non_neg_integer(), data_delta()} | {:insert, non_neg_integer(), data()}
  @type data_delta() ::
          nil
          | :drop
          | {:data, data()}
          | {:list, [list_delta()]}
          | {:map, %{required(String.t()) => data_delta()}}
end
