defmodule Axiom.Domain do
  @moduledoc "Pure validation and canonical representation; never evaluates authorization."
  @kinds ~w(person service team document project)
  @resource_kinds ~w(document project)
  @max_revision 9_223_372_036_854_775_807

  def identifier(value),
    do:
      is_binary(value) and byte_size(value) <= 64 and
        Regex.match?(~r/\A[a-z][a-z0-9_.-]*\z/, value)

  def identifiers(values), do: Enum.all?(values, &identifier/1)
  def revision(value), do: is_integer(value) and value >= 0 and value <= @max_revision

  def next_revision(value) do
    cond do
      not revision(value) -> {:error, :invalid_revision}
      value == @max_revision -> {:error, :revision_exhausted}
      true -> {:ok, value + 1}
    end
  end

  def kind(value), do: value in @kinds
  def status(value), do: value in ["active", "suspended"]
  def assignment_status(value), do: value in ["active", "revoked"]
  def principal_kind(value), do: value in ["person", "service"]
  def resource_kind(value), do: value in @resource_kinds

  def policy(body, roles) do
    cond do
      not is_map(body) ->
        {:error, :invalid_policy}

      Enum.sort(Map.keys(body)) != ["rules", "schema_version"] ->
        {:error, :invalid_policy}

      body["schema_version"] != 1 ->
        {:error, :unsupported_schema}

      not is_list(body["rules"]) or length(body["rules"]) not in 1..100 ->
        {:error, :invalid_rules}

      true ->
        validate_rules(body["rules"], MapSet.new(roles))
    end
  end

  defp validate_rules(rules, roles) do
    Enum.reduce_while(rules, {:ok, %{"schema_version" => 1, "rules" => rules}}, fn rule, ok ->
      cond do
        not is_map(rule) ->
          {:halt, {:error, :invalid_rule}}

        Enum.sort(Map.keys(rule)) != ["actions", "effect", "resource_kind", "role"] ->
          {:halt, {:error, :invalid_rule}}

        rule["effect"] not in ["allow", "deny"] ->
          {:halt, {:error, :invalid_effect}}

        not identifier(rule["role"]) ->
          {:halt, {:error, :invalid_role}}

        not MapSet.member?(roles, rule["role"]) ->
          {:halt, {:error, :unknown_role}}

        not resource_kind(rule["resource_kind"]) ->
          {:halt, {:error, :invalid_resource_kind}}

        not is_list(rule["actions"]) or length(rule["actions"]) not in 1..32 ->
          {:halt, {:error, :invalid_actions}}

        not identifiers(rule["actions"]) or
            length(Enum.uniq(rule["actions"])) != length(rule["actions"]) ->
          {:halt, {:error, :invalid_actions}}

        true ->
          {:cont, ok}
      end
    end)
  end

  def relation(subject_kind, relation, object_kind) do
    principal_kind(subject_kind) and
      ((relation == "member" and object_kind == "team") or
         (relation == "owner" and resource_kind(object_kind)))
  end

  # Keys are sorted recursively; this is a v1-local canonical format, not an external standard.
  def canonical(value) when is_map(value) do
    "{" <>
      (value
       |> Enum.sort_by(&elem(&1, 0))
       |> Enum.map_join(",", fn {k, v} -> Jason.encode!(k) <> ":" <> canonical(v) end)) <> "}"
  end

  def canonical(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical/1) <> "]"

  def canonical(value), do: Jason.encode!(value)
  def digest(value), do: :crypto.hash(:sha256, canonical(value)) |> Base.encode16(case: :lower)

  def etag(data), do: "\"" <> digest(data) <> "\""
end
