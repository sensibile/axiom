Code.prepend_path("_build/dev/lib/jason/ebin")
Code.require_file("lib/axiom/domain.ex")
alias Axiom.Domain
body = %{"schema_version" => 1, "rules" => [%{"effect" => "allow", "role" => "reader", "resource_kind" => "document", "actions" => ["read"]}]}
checks = [
  {"valid policy", match?({:ok, _}, Domain.policy(body, ["reader"]))},
  {"unknown role rejected", Domain.policy(body, []) == {:error, :unknown_role}},
  {"executable field rejected", Domain.policy(Map.put(body, "code", "System.cmd"), ["reader"]) == {:error, :invalid_policy}},
  {"SQL identifier rejected", not Domain.identifier("x';drop table axiom_tenants;--")},
  {"too many rules rejected", Domain.policy(%{body | "rules" => List.duplicate(hd(body["rules"]), 101)}, ["reader"]) == {:error, :invalid_rules}},
  {"untyped relation rejected", not Domain.relation("person", "owner", "person")},
  {"canonical order stable", Domain.digest(%{"a" => 1, "b" => 2}) == Domain.digest(%{"b" => 2, "a" => 1})}
]
Enum.each(checks, fn {label, pass} -> IO.puts("#{label}: #{pass}"); if not pass, do: raise(label) end)
IO.inspect(Domain.policy(%{body | "schema_version" => 1.0}, ["reader"]), label: "float schema version observation")
for {label, input} <- [{"invalid UTF8", <<255>>}, {"oversized identifier", String.duplicate("a", 65)}] do
  result = try do Domain.identifier(input) rescue e -> {:raised, e.__struct__} end
  IO.inspect(result, label: label)
end
for n <- [1_000, 100_000] do
  oversized = %{body | "rules" => List.duplicate(nil, n)}
  {us, result} = :timer.tc(fn -> Domain.policy(oversized, ["reader"]) end)
  IO.inspect({n, result, us}, label: "oversized rule validation (microseconds)")
end
