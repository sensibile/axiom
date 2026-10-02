Code.compile_string(File.read!(Path.join(__DIR__, "original-pure-module.exs")) |> String.replace("defmodule Axiom.Domain do", "defmodule BeforeCleanup.Domain do"))
values = [nil, false, true, -1, 0, 1, "", "read", [], ["read"], ["read", "read"], ["bad action"], Enum.map(1..33, &"action#{&1}"), %{}, [1 | 2]]
base = %{"actions" => ["read"], "effect" => "allow", "resource_kind" => "document", "role" => "reader"}
rules = values ++ for(key <- Map.keys(base), value <- values, do: Map.put(base, key, value))
inputs = for(rule <- rules, schema <- [0, 1, nil], do: %{"rules" => [rule], "schema_version" => schema})
observe = fn fun ->
  try do
    {:returned, fun.()}
  rescue
    error -> {:raised, error.__struct__, Exception.message(error)}
  end
end
for input <- inputs, roles <- [[], ["reader"]] do
  before = observe.(fn -> BeforeCleanup.Domain.policy(input, roles) end)
  after_cleanup = observe.(fn -> Axiom.Domain.policy(input, roles) end)
  unless before == after_cleanup, do: raise("policy behavior differs")
end
IO.puts("Policy equivalence: #{length(inputs) * 2} inputs/roles matched")
