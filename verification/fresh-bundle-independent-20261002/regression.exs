run_id = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
Application.put_env(:axiom, :independent_run, run_id)
IO.inspect(run_id, label: "fixture_run_namespace")
ExUnit.start(seed: 20_261_002)
root = Path.expand("../..", __DIR__)
opts = Axiom.TestDatabase.options()
{:ok, identity} = Postgrex.start_link(Keyword.put(opts, :parameters, []))
Process.unlink(identity)
q = fn sql -> Postgrex.query!(identity, sql, []).rows end

[["axiom_test", "axiom_test", 5432, version, address]] =
  q.(
    "SELECT current_database(),current_user,inet_server_port(),current_setting('server_version_num')::integer,inet_server_addr()::text"
  )

true = version >= 170_000 and version < 180_000

IO.inspect(
  %{
    database: "axiom_test",
    user: "axiom_test",
    server_port: 5432,
    version: version,
    address: address
  },
  label: "verified_identity"
)

public = fn ->
  for [table] <-
        q.("SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename") do
    [
      table,
      q.("SELECT row_to_json(t)::text FROM public.\"#{table}\" t ORDER BY row_to_json(t)::text")
    ]
  end
end

before = public.()
File.write!(Path.join(__DIR__, "public-before.json"), Jason.encode!(before))
schema = "axiom_independent_bundle_20261002"
q.("CREATE SCHEMA IF NOT EXISTS #{schema}")

{_, 0} =
  System.cmd(
    "psql",
    [
      "-X",
      "--no-password",
      "--set",
      "ON_ERROR_STOP=1",
      "--host",
      opts[:hostname],
      "--port",
      to_string(opts[:port]),
      "--username",
      opts[:username],
      "--dbname",
      opts[:database],
      "--file",
      Path.join(root, "priv/schema.sql")
    ],
    env: [{"PGPASSWORD", opts[:password]}, {"PGOPTIONS", "-c search_path=#{schema}"}],
    stderr_to_stdout: true
  )

{:ok, conn} = Postgrex.start_link(Keyword.put(opts, :parameters, search_path: schema))
Process.unlink(conn)
Application.put_env(:axiom, :independent_conn, conn)

Application.put_env(
  :axiom,
  :independent_opts,
  Keyword.put(opts, :parameters, search_path: schema)
)

ExUnit.after_suite(fn _ ->
  after_rows = public.()
  File.write!(Path.join(__DIR__, "public-after.json"), Jason.encode!(after_rows))
  IO.inspect(before == after_rows, label: "public_preserved")
end)


Application.put_env(:axiom, :test_conn, conn)
Code.require_file("test/domain_test.exs")
Code.require_file("test/service_test.exs")
Code.require_file("test/resource_scope_test.exs")
Code.require_file("test/counter_exhaustion_test.exs")
Code.require_file("verification/independent_test.exs")
Code.require_file("verification/counter_boundary_test.exs")
