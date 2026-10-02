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
schema = "axiom_independent_scope_20261002"
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

defmodule IndependentScopeProbe do
  use ExUnit.Case, async: false
  defp q(c, sql, args \\ []), do: Postgrex.query!(c, sql, args).rows

  defp scope(t, space \\ "space", scenario \\ "base"),
    do: %{"tenant_id" => t, "space_id" => space, "scenario_id" => scenario, "local_id" => "same"}

  defp ok({:ok, value}), do: value

  defp rev(c, t),
    do: q(c, "SELECT assignment_revision FROM axiom_tenants WHERE id=$1", [t]) |> hd() |> hd()

  defp fixture do
    c = Application.fetch_env!(:axiom, :independent_conn)

    t =
      "i" <>
        Application.fetch_env!(:axiom, :independent_run) <>
        Integer.to_string(System.unique_integer([:positive]))

    ok(Axiom.create_tenant(c, t))
    ok(Axiom.register_role(c, t, "reader", 0, "actor"))
    ok(Axiom.register_node(c, t, "person", "person", 1, "actor"))
    s = scope(t)
    ok(Axiom.register_resource_scope(c, s, "document", 2, "actor"))

    body = %{
      "schema_version" => 1,
      "rules" => [
        %{
          "role" => "reader",
          "resource_kind" => "document",
          "actions" => ["read"],
          "effect" => "allow"
        }
      ]
    }

    ok(Axiom.save_draft(c, t, body, 0))
    p = ok(Axiom.publish(c, t, 1, 0, "publish", "actor"))
    {c, t, s, p}
  end

  test "exact tuple namespace, validation, no inherited/default/wildcard authority and ETag binding" do
    {c, t, s, _} = fixture()
    ok(Axiom.put_resource_assignment(c, s, "person", "reader", "active", 3, "actor"))
    ok(Axiom.put_resource_relation(c, s, "person", "owner", "active", 4, "actor"))
    a = ok(Axiom.resource_snapshot(c, s, "person"))

    for other <- [scope(t, "other"), scope(t, "space", "fork")] do
      ok(Axiom.register_resource_scope(c, other, "document", rev(c, t), "actor"))
      b = ok(Axiom.resource_snapshot(c, other, "person", if_none_match: a["etag"]))
      assert b["status"] == "ok"
      assert b["data"]["assignments"] == [] and b["data"]["relations"] == []
      refute b["etag"] == a["etag"]
    end

    for bad <- [
          nil,
          %{},
          Map.delete(s, "scenario_id"),
          Map.put(s, "scenario_id", "*"),
          Map.put(s, "space_id", ""),
          Map.put(s, "local_id", String.duplicate("a", 65)),
          Map.put(s, "table", "physical"),
          Map.put(s, "tenant_id", :atom),
          Map.put(s, "scenario_id", "BASE")
        ] do
      assert Axiom.register_resource_scope(c, bad, "document", rev(c, t), "actor") ==
               {:error, :invalid_scope}

      assert Axiom.resource_snapshot(c, bad, "person") == {:error, :invalid_scope}

      assert Axiom.put_resource_assignment(
               c,
               bad,
               "person",
               "reader",
               "active",
               rev(c, t),
               "actor"
             ) == {:error, :invalid_scope}

      assert Axiom.put_resource_relation(c, bad, "person", "owner", "active", rev(c, t), "actor") ==
               {:error, :invalid_scope}
    end

    assert Axiom.resource_snapshot(c, scope(t, "unknown"), "person") == {:error, :scope_not_found}

    for opts <- [[query_cut: 1], [release_id: 1, release_id: 2], %{}, [unknown: nil]] do
      assert Axiom.resource_snapshot(c, s, "person", opts) == {:error, :invalid_options}
    end

    assert a["data"]["assignments"] == [%{"role" => "reader", "scope" => s, "status" => "active"}]

    assert a["data"]["relations"] == [
             %{"relation" => "owner", "object" => s, "status" => "active"}
           ]

    assert a["data"]["consumer_contract"]["knowledge_cut"] == "external_not_verified"
    assert a["data"]["consumer_contract"]["decision"] == "not_evaluated"

    assert Axiom.register_resource_scope(c, s, "document", rev(c, t), "actor") ==
             {:error, :scope_collision}

    assert Axiom.put_resource_assignment(c, s, "person", "missing", "active", rev(c, t), "actor") ==
             {:error, :unknown_role}

    assert Axiom.put_resource_relation(c, s, "person", "member", "active", rev(c, t), "actor") ==
             {:error, :invalid_relation}

    {_, t2, s2, p2} = fixture()
    assert t != t2
    ok(Axiom.register_node(c, t2, "foreign", "person", rev(c, t2), "actor"))

    assert Axiom.put_resource_assignment(c, s, "foreign", "reader", "active", rev(c, t), "actor") ==
             {:error, :node_not_found}

    assert Axiom.snapshot(c, t, "person", resource_scope: s2) == {:error, :invalid_scope}
    assert ok(Axiom.resource_snapshot(c, s2, "person"))["data"]["assignments"] == []

    assert Axiom.resource_snapshot(c, s, "person", release_id: p2["policy_release_id"]) ==
             {:error, :release_not_found}
  end

  test "historical policy, rollback, suspension, cache invalidation, idempotency conflicts" do
    {c, t, s, p} = fixture()
    ok(Axiom.put_resource_assignment(c, s, "person", "reader", "active", 3, "actor"))
    old = ok(Axiom.resource_snapshot(c, s, "person"))
    ok(Axiom.put_resource_assignment(c, s, "person", "reader", "revoked", 4, "actor"))
    ok(Axiom.set_principal_status(c, t, "person", "suspended", 5, "actor"))
    rb = ok(Axiom.rollback_policy(c, t, p["policy_release_id"], 1, "rollback", "actor", "review"))

    assert ok(
             Axiom.rollback_policy(c, t, p["policy_release_id"], 1, "rollback", "actor", "review")
           ) == rb

    assert Axiom.rollback_policy(
             c,
             t,
             p["policy_release_id"],
             1,
             "rollback",
             "actor",
             "different"
           ) == {:error, :idempotency_conflict}

    assert Axiom.publish(c, t, 1, 0, "publish", "other") == {:error, :idempotency_conflict}

    now =
      ok(
        Axiom.resource_snapshot(c, s, "person",
          release_id: p["policy_release_id"],
          if_none_match: old["etag"]
        )
      )

    assert now["status"] == "ok"
    d = now["data"]

    assert d["principal_status"] == "suspended" and d["assignment_revision"] == 6 and
             d["policy_generation"] == 2

    assert hd(d["assignments"])["status"] == "revoked"
    assert d["policy_head_release_id"] == p["policy_release_id"]

    assert ok(Axiom.resource_snapshot(c, s, "person", if_none_match: now["etag"])) == %{
             "status" => "not_modified",
             "etag" => now["etag"]
           }

    assert Axiom.put_resource_assignment(c, s, "person", "reader", "active", 4, "actor") ==
             {:error, :conflict}

    assert Enum.map(ok(Axiom.history(c, t))["assignments"], &hd/1) == Enum.to_list(1..6)
  end

  test "actual concurrent CAS writes produce one committed event" do
    {c, t, s, _} = fixture()

    tasks =
      for _ <- 1..6,
          do:
            Task.async(fn ->
              Axiom.put_resource_assignment(c, s, "person", "reader", "active", 3, "actor")
            end)

    results = Enum.map(tasks, &Task.await/1)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :conflict})) == 5
    assert rev(c, t) == 4

    assert q(
             c,
             "SELECT count(*) FROM axiom_assignment_events WHERE tenant_id=$1 AND revision=4",
             [t]
           ) == [[1]]
  end

  test "scoped bigint last value and exhaustion stay atomic" do
    {c, t, s, _} = fixture()
    max = 9_223_372_036_854_775_807
    q(c, "UPDATE axiom_tenants SET assignment_revision=$2 WHERE id=$1", [t, max - 1])

    assert ok(Axiom.put_resource_assignment(c, s, "person", "reader", "active", max - 1, "actor"))[
             "assignment_revision"
           ] == max

    before = ok(Axiom.resource_snapshot(c, s, "person"))
    assert before["data"]["assignment_revision"] == max

    assert Axiom.put_resource_assignment(c, s, "person", "reader", "revoked", max, "actor") ==
             {:error, :revision_exhausted}

    assert Axiom.register_resource_scope(c, scope(t, "new"), "document", max, "actor") ==
             {:error, :revision_exhausted}

    for bad <- [-1, max + 1, 1.0, "3", nil] do
      assert Axiom.put_resource_assignment(c, s, "person", "reader", "active", bad, "actor") ==
               {:error, :invalid_revision}
    end

    assert ok(Axiom.resource_snapshot(c, s, "person")) == before
  end

  test "API repeatable-read cannot mix pre-commit head with post-commit revocation" do
    {c, t, s, p} = fixture()
    ok(Axiom.put_resource_assignment(c, s, "person", "reader", "active", 3, "actor"))
    opts = Application.fetch_env!(:axiom, :independent_opts)
    {:ok, holder_conn} = Postgrex.start_link(opts)
    parent = self()

    holder =
      Task.async(fn ->
        Postgrex.transaction(holder_conn, fn tx ->
          q(tx, "LOCK TABLE axiom_releases IN ACCESS EXCLUSIVE MODE")
          send(parent, :locked)

          receive do
            :unlock -> :ok
          after
            10000 -> raise "gate timeout"
          end
        end)
      end)

    assert_receive :locked, 2000
    reader = Task.async(fn -> Axiom.resource_snapshot(c, s, "person") end)

    blocked =
      Enum.reduce_while(1..100, false, fn _, _ ->
        rows =
          q(
            c,
            "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock' AND query LIKE 'SELECT body,digest FROM axiom_releases%'"
          )

        if rows == [[1]],
          do: {:halt, true},
          else:
            (
              Process.sleep(10)
              {:cont, false}
            )
      end)

    assert blocked
    ok(Axiom.put_resource_assignment(c, s, "person", "reader", "revoked", 4, "actor"))
    ok(Axiom.set_principal_status(c, t, "person", "suspended", 5, "actor"))
    send(holder.pid, :unlock)
    Task.await(holder)
    observed = ok(Task.await(reader))["data"]
    assert observed["assignment_revision"] == 4
    assert observed["principal_status"] == "active"
    assert hd(observed["assignments"])["status"] == "active"
    assert observed["policy_head_release_id"] == p["policy_release_id"]
    current = ok(Axiom.resource_snapshot(c, s, "person"))["data"]
    assert current["assignment_revision"] == 6
    assert current["principal_status"] == "suspended"
    assert hd(current["assignments"])["status"] == "revoked"

    IO.inspect(
      %{
        blocked_after_identity: blocked,
        snapshot_revision: observed["assignment_revision"],
        committed_revision: current["assignment_revision"]
      },
      label: "read_snapshot_trace"
    )

    GenServer.stop(holder_conn)
  end

  test "historical selected policy stays separate from newer head and current revocation" do
    {c, t, scope, p} = fixture()
    ok(Axiom.put_resource_assignment(c, scope, "person", "reader", "active", 3, "actor"))

    policy = %{
      "schema_version" => 1,
      "rules" => [
        %{
          "role" => "reader",
          "resource_kind" => "document",
          "actions" => ["write"],
          "effect" => "deny"
        }
      ]
    }

    ok(Axiom.save_draft(c, t, policy, 1))
    newer = ok(Axiom.publish(c, t, 2, 1, "newer", "actor"))
    ok(Axiom.put_resource_assignment(c, scope, "person", "reader", "revoked", 4, "actor"))

    selected =
      ok(Axiom.resource_snapshot(c, scope, "person", release_id: p["policy_release_id"]))["data"]

    assert selected["policy"]["release_id"] == p["policy_release_id"]
    assert selected["policy_head_release_id"] == newer["policy_release_id"]
    assert selected["policy_generation"] == 2 and selected["assignment_revision"] == 5
    assert hd(selected["assignments"])["status"] == "revoked"
    assert hd(selected["policy"]["body"]["rules"])["actions"] == ["read"]
    assert ok(Axiom.publish(c, t, 1, 0, "publish", "actor")) == p
  end
end
