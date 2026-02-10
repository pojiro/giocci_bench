defmodule GiocciBench.Csv do
  @moduledoc false

  alias NimbleCSV.RFC4180, as: CSV

  def write_csv!(path, header, rows) when is_list(header) and is_list(rows) do
    assert_row_sizes!(header, rows)

    content =
      [header | rows]
      |> Enum.map(&normalize_row/1)
      |> CSV.dump_to_iodata()
      |> IO.iodata_to_binary()

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end

  defp assert_row_sizes!(header, rows) do
    header_len = length(header)

    case Enum.find_index(rows, &(length(&1) != header_len)) do
      nil ->
        :ok

      index ->
        raise ArgumentError,
              "CSV row length mismatch at index #{index}: expected #{header_len}"
    end
  end

  defp normalize_row(values) do
    Enum.map(values, &normalize_value/1)
  end

  defp normalize_value(nil), do: ""
  defp normalize_value(value) when is_binary(value), do: clean_text(value)
  defp normalize_value(value) when is_boolean(value), do: to_string(value)
  defp normalize_value(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_value(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 3)
  defp normalize_value(value), do: normalize_value(to_string(value))

  defp clean_text(value) do
    String.replace(value, ["\r", "\n"], " ")
  end
end
