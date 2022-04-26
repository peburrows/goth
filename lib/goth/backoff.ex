# Based on:
# https://github.com/elixir-ecto/db_connection/blob/v2.3.0/lib/db_connection/backoff.ex

defmodule Goth.Backoff do
  @moduledoc false

  require Bitwise

  alias __MODULE__

  defstruct [:type, :min, :max, :state]

  @typedoc """
  Supported backoff type generators.
  """
  @type backoff_type :: :rand | :exp | :rand_exp

  @supported_types [:rand, :exp, :rand_exp]

  @typedoc """
  ## Fields

    * `type`  - Defines the backoff type to be used
                for min/max generation.

    * `min`   - Minimum value to be used.

    * `max`   - Maxmum value to be used.

    * `state` - Current state for given `type`.
  """
  @type t :: %__MODULE__{
          type: backoff_type(),
          min: pos_integer(),
          max: pos_integer(),
          state: state()
        }

  @typedoc """
  Current state from Backoff last number generated.
  """
  @type state :: nil | {pos_integer(), t()} | {pos_integer(), pos_integer(), t()}

  @default_type :rand_exp

  @doc """
  Creates a new Backoff struct with given options.

  ## Options:

    * `type` - Defines the backoff type to generate the backoff state.
               Default: `:rand_exp`

    * `min`  - Defines the minimum value.
               Default: `1_000`

    * `max`  - Defines the maximum value.
               Default: `30_000`

  """
  @spec new!(keyword()) :: t()
  def new!(opts) do
    case Keyword.get(opts, :type, @default_type) do
      type when type in @supported_types ->
        {min, max} = min_max(opts)
        new(type, min, max)

      type ->
        raise ArgumentError, "Unsupported backoff type: #{inspect(type)}"
    end
  end

  @doc """
  Generates the current backoff time to be used and
  returns a new state to generate the next one.

  ## Examples

      iex> Backoff.backoff(%Backoff{})
      {1_000, %Backoff{}}

  """
  @spec backoff(t()) :: {pos_integer(), t()}
  def backoff(backoff)

  def backoff(%Backoff{type: :rand, min: min, max: max, state: state} = backoff) do
    {value, state} = rand(state, min, max)
    {value, %Backoff{backoff | state: state}}
  end

  def backoff(%Backoff{type: :exp, min: min, state: nil} = backoff) do
    {min, %Backoff{backoff | state: min}}
  end

  def backoff(%Backoff{type: :exp, max: max, state: prev} = backoff) do
    next = min(Bitwise.<<<(prev, 1), max)
    {next, %Backoff{backoff | state: next}}
  end

  def backoff(%Backoff{type: :rand_exp, max: max, state: {prev, lower, state}} = backoff) do
    next_min = min(prev, lower)
    next_max = min(prev * 3, max)
    {next, state} = rand(state, next_min, next_max)

    {next, %Backoff{backoff | state: {next, lower, state}}}
  end

  @doc """
  Resets backoff state to initial state based on his type.

  ## Examples

      iex> Backoff.reset(%Backoff{type: :exp, state: 123})
      %Backoff{type: :exo, state: nil}

  """
  @spec reset(t()) :: t()
  def reset(backoff)

  def reset(%Backoff{type: :rand} = backoff), do: backoff
  def reset(%Backoff{type: :exp} = backoff), do: %Backoff{backoff | state: nil}

  def reset(%Backoff{type: :rand_exp, min: min, state: {_, lower, state}} = backoff) do
    %Backoff{backoff | state: {min, lower, state}}
  end

  ## Internal

  @min 1_000
  @max 30_000

  defp min_max(opts) do
    case {opts[:min], opts[:max]} do
      {nil, nil} -> {@min, @max}
      {nil, max} -> {min(@min, max), max}
      {min, nil} -> {min, max(min, @max)}
      {min, max} -> {min, max}
    end
  end

  defp new(_, min, _) when not (is_integer(min) and min >= 0) do
    raise ArgumentError, "minimum #{inspect(min)} not 0 or a positive integer"
  end

  defp new(_, _, max) when not (is_integer(max) and max >= 0) do
    raise ArgumentError, "maximum #{inspect(max)} not 0 or a positive integer"
  end

  defp new(_, min, max) when min > max do
    raise ArgumentError, "minimum #{min} is greater than maximum #{max}"
  end

  defp new(:rand, min, max) do
    %Backoff{type: :rand, min: min, max: max, state: seed()}
  end

  defp new(:exp, min, max) do
    %Backoff{type: :exp, min: min, max: max, state: nil}
  end

  defp new(:rand_exp, min, max) do
    lower = max(min, div(max, 3))
    %Backoff{type: :rand_exp, min: min, max: max, state: {min, lower, seed()}}
  end

  defp seed() do
    :rand.seed_s(:exsplus)
  end

  defp rand(state, min, max) do
    {int, state} = :rand.uniform_s(max - min + 1, state)
    {int + min - 1, state}
  end
end
