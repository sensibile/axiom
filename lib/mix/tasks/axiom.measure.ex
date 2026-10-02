defmodule Mix.Tasks.Axiom.Measure do
  @moduledoc "Measure service boundary latency against the project-only test database."
  use Mix.Task
  @shortdoc "Measure the local axiom test DB service boundary, without exposing a server"
  def run(_) do
    Mix.Task.run("app.start")
    Axiom.TestDatabase.prepare!()
    {:ok, conn} = Postgrex.start_link(Axiom.TestDatabase.options())
    tenant = "measure-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    {:ok, _} = Axiom.create_tenant(conn, tenant)
    {:ok, _} = Axiom.register_role(conn, tenant, "reader", 0, "admin")
    {:ok, _} = Axiom.register_node(conn, tenant, "alice", "person", 1, "admin")
    {:ok, _} = Axiom.register_node(conn, tenant, "doc", "document", 2, "admin")
    {:ok, _} = Axiom.put_assignment(conn, tenant, "alice", "reader", "doc", "active", 3, "admin")

    body = %{
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

    {:ok, _} = Axiom.save_draft(conn, tenant, body, 0)
    {:ok, _} = Axiom.publish(conn, tenant, 1, 0, "initial", "admin")
    for _ <- 1..10, do: Axiom.snapshot(conn, tenant, "alice")

    reads =
      for _ <- 1..100 do
        {us, {:ok, _}} = :timer.tc(fn -> Axiom.snapshot(conn, tenant, "alice") end)
        us
      end

    publications =
      for n <- 1..20 do
        {:ok, _} = Axiom.save_draft(conn, tenant, body, n)

        {us, {:ok, _}} =
          :timer.tc(fn -> Axiom.publish(conn, tenant, n + 1, n, "measure-#{n}", "admin") end)

        us
      end

    bytes =
      Axiom.Store.query(
        conn,
        "SELECT pg_column_size(body) FROM axiom_releases WHERE tenant_id=$1 ORDER BY id LIMIT 1",
        [tenant]
      )
      |> hd()
      |> hd()

    result = %{
      "dataset" => %{
        "rules" => 1,
        "roles" => 1,
        "principals" => 1,
        "assignments" => 1,
        "jsonb_bytes" => bytes
      },
      "snapshot_us" => stats(reads),
      "publish_us" => stats(publications),
      "notes" =>
        "local serial warm service calls; includes transaction/network; draft save excluded from publication timing; not a capacity claim"
    }

    Mix.shell().info(Jason.encode!(result, pretty: true))
    GenServer.stop(conn)
  end

  defp stats(samples) do
    sorted = Enum.sort(samples)

    %{
      "n" => length(samples),
      "min" => hd(sorted),
      "median" => Enum.at(sorted, div(length(sorted), 2)),
      "p95" => Enum.at(sorted, ceil(length(sorted) * 0.95) - 1),
      "max" => List.last(sorted)
    }
  end
end
