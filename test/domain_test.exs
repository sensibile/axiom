defmodule Axiom.DomainTest do
  use ExUnit.Case, async: true
  alias Axiom.Domain

  def policy,
    do: %{
      "schema_version" => 1,
      "rules" => [
        %{
          "effect" => "allow",
          "role" => "reader",
          "actions" => ["read"],
          "resource_kind" => "document"
        }
      ]
    }

  test "limited schema and references reject executable or unknown fields" do
    assert {:ok, _} = Domain.policy(policy(), ["reader"])
    assert {:error, :unknown_role} = Domain.policy(policy(), [])

    assert {:error, :invalid_policy} =
             Domain.policy(Map.put(policy(), "code", "System.cmd"), ["reader"])

    assert {:error, :unsupported_schema} =
             Domain.policy(%{policy() | "schema_version" => 2}, ["reader"])

    for input <- [nil, "policy", [], %{}, %{"schema_version" => 1, "rules" => [nil]}] do
      assert {:error, _} = Domain.policy(input, ["reader"])
    end

    bad = put_in(policy(), ["rules", Access.at(0), "actions"], ["read", "read"])
    assert {:error, :invalid_actions} = Domain.policy(bad, ["reader"])
    assert not Domain.identifier("a'; DROP TABLE x")
    assert not Domain.identifier(String.duplicate("a", 65))
  end

  test "policy schema versions and CAS revisions require integers" do
    for value <- [1.0, 1.5, true, false, nil, "1", [], %{}, %{1 => 1}] do
      assert {:error, :unsupported_schema} =
               Domain.policy(Map.put(policy(), "schema_version", value), ["reader"])

      refute Domain.revision(value)
    end

    assert Domain.revision(0)
    assert Domain.revision(9_223_372_036_854_775_807)
    refute Domain.revision(9_223_372_036_854_775_808)
  end

  test "relation domain permits direct typed edges only" do
    assert Domain.relation("person", "member", "team")
    assert Domain.relation("service", "owner", "document")
    refute Domain.relation("team", "member", "team")
    refute Domain.relation("person", "owner", "person")
    refute Domain.relation("person", "admin", "project")
  end

  test "canonical digest is independent of map insertion order" do
    assert Domain.canonical(%{"b" => 2, "a" => %{"z" => 1}}) == "{\"a\":{\"z\":1},\"b\":2}"
    assert Domain.digest(%{"a" => 1, "b" => 2}) == Domain.digest(%{"b" => 2, "a" => 1})
    refute Domain.digest([1, 2]) == Domain.digest([2, 1])
  end
end
