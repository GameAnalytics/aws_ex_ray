  defmodule AwsExRay.Stacktrace do

    @moduledoc ~S"""
    This module provides a function which gathers stacktrace
    and format them for **error.cause** report.
    """

    @spec stacktrace(non_neg_integer) :: list
    def stacktrace(discard_num \\ 0) do

      {:current_stacktrace, list} = Process.info(self(), :current_stacktrace)

      # Ignore first and second
      # 0: AwsExRay.Util.stacktrace
      # 1: Process.info
      list |> Enum.drop(2 + discard_num) |> Enum.map(&to_map/1)

    end

    def to_map({module, fun, args, [file: path, line: line]}) do
      arity = cond do
        is_integer(args) -> args
        is_list(args) -> length(args)
      end
      %{
        path: "#{path}",
        line: line,
        label: "#{module}.#{fun_name(fun)}/#{arity}"
      }
    end

    defp fun_name(":" <> fun), do: fun
    defp fun_name(fun), do: fun

  end
