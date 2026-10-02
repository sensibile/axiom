defmodule Axiom.TestDatabase do
  @moduledoc "Explicit project-only local test DB configuration. Never defaults to an existing DB."
  def options do
    [
      hostname: "127.0.0.1",
      port: 55_439,
      database: "axiom_test",
      username: "axiom_test",
      password: "axiom_local_only",
      parameters: [search_path: "axiom_revision_bundle_20261002"],
      pool_size: 6,
      pool: DBConnection.ConnectionPool
    ]
  end

  def prepare! do
    opts = options()
    verify_and_namespace!(opts)

    {output, code} =
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
          Path.expand("../../priv/schema.sql", __DIR__)
        ],
        env: [
          {"PGPASSWORD", opts[:password]},
          {"PGOPTIONS", "-c search_path=axiom_revision_bundle_20261002"}
        ],
        stderr_to_stdout: true
      )

    if code != 0, do: raise("axiom test DB setup failed: #{output}")
    :ok
  end

  defp verify_and_namespace!(opts) do
    {:ok, conn} = Postgrex.start_link(opts)

    try do
      result =
        Postgrex.query!(
          conn,
          "SELECT current_database(),current_user,inet_server_port(),current_setting('server_version_num')::integer",
          []
        )

      case result.rows do
        [["axiom_test", "axiom_test", 5432, version]]
        when version >= 170_000 and version < 180_000 ->
          Postgrex.query!(conn, "CREATE SCHEMA IF NOT EXISTS axiom_revision_bundle_20261002", [])

        _ ->
          raise "test database identity mismatch"
      end
    after
      GenServer.stop(conn)
    end
  end
end
