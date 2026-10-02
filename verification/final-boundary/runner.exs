evidence_dir = System.get_env("AXIOM_FINAL_EVIDENCE_DIR") || "verification/final-boundary/replay-#{System.system_time(:microsecond)}"
File.mkdir_p!(evidence_dir)
{:ok, _} = Application.ensure_all_started(:postgrex)
{:ok, c} = Postgrex.start_link(Axiom.TestDatabase.options())
Process.unlink(c)
Application.put_env(:axiom, :test_conn, c)
alias Axiom.Store
[["axiom_test", "axiom_test", 5432]] = Store.query(c, "SELECT current_database(),current_user,inet_server_port()")
IO.inspect(Store.query(c,"SELECT version()"),label: "PG identity")
tables = ~w(axiom_tenants axiom_roles axiom_nodes axiom_drafts axiom_releases axiom_assignments axiom_relations axiom_assignment_events axiom_publications)
original = Map.new(tables,fn table -> {table,Store.query(c,"SELECT row_to_json(t)::text FROM #{table} t ORDER BY row_to_json(t)::text")} end)
File.write!(Path.join(evidence_dir,"db-before.json"),Jason.encode!(original))
ExUnit.start(seed: 8102026)
for file <- ~w(test/domain_test.exs test/service_test.exs test/counter_exhaustion_test.exs verification/counter_boundary_test.exs verification/independent_test.exs verification/final-boundary/independent.exs), do: Code.require_file(file)
ExUnit.after_suite(fn result ->
  preservation=Map.new(original,fn {table,rows}->
    current=Store.query(c,"SELECT row_to_json(t)::text FROM #{table} t ORDER BY row_to_json(t)::text")
    {table,Enum.all?(rows,&(&1 in current))}
  end)
  File.write!(Path.join(evidence_dir,"db-preservation.json"),Jason.encode!(preservation))
  IO.inspect(preservation,label: "preexisting row preservation")
  IO.inspect(result,label: "aggregate")
end)
