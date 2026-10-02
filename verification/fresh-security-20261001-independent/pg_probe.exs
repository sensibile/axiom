for name <- ~w(decimal telemetry db_connection jason postgrex), do: Code.prepend_path("_build/dev/lib/#{name}/ebin")
for path <- ~w(lib/axiom/domain.ex lib/axiom/store.ex lib/axiom.ex lib/axiom/test_database.ex), do: Code.require_file(path)
{:ok, _} = Application.ensure_all_started(:postgrex)
{:ok, c} = Postgrex.start_link(Axiom.TestDatabase.options())
alias Axiom.Store
[["axiom_test", "axiom_test"]] = Store.query(c, "SELECT current_database(),current_user")
ExUnit.start()
defmodule IndependentSecurityPG do
  use ExUnit.Case, async: false
  alias Axiom.Store
  defp body(action), do: %{"schema_version" => 1, "rules" => [%{"effect" => "allow", "role" => "reader", "resource_kind" => "document", "actions" => [action]}]}
  setup_all do
    {:ok, c} = Postgrex.start_link(Axiom.TestDatabase.options())
    tenants = for _ <- 1..2 do
      t = "sec-fresh-" <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
      {:ok, _} = Axiom.create_tenant(c, t)
      {:ok, _} = Axiom.register_role(c, t, "reader", 0, "verifier")
      {:ok, _} = Axiom.register_node(c, t, "alice", "person", 1, "verifier")
      {:ok, _} = Axiom.register_node(c, t, "doc", "document", 2, "verifier")
      {:ok, _} = Axiom.register_node(c, t, "team", "team", 3, "verifier")
      t
    end
    IO.inspect(tenants, label: "new fixture tenants (retained)")
    on_exit(fn -> if Process.alive?(c), do: GenServer.stop(c) end)
    {:ok, c: c, t: hd(tenants), other: List.last(tenants)}
  end
  test "independent boundary invariants", %{c: c, t: t, other: other} do
    assert {:error, :invalid_identifier} = Axiom.register_role(c, t, "x';DROP TABLE axiom_tenants;--", 4, "verifier")
    assert {:error, :invalid_identifier} = Axiom.snapshot(c, "x' OR 1=1--", "alice")
    assert {:error, :unknown_role} = Axiom.save_draft(c, t, put_in(body("read"), ["rules", Access.at(0), "role"], "missing"), 0)
    assert {:ok, _} = Axiom.register_role(c, other, "only-other-role", 4, "verifier")
    assert {:error, :unknown_role} = Axiom.save_draft(c, t, put_in(body("read"), ["rules", Access.at(0), "role"], "only-other-role"), 0)
    assert {:ok, _} = Axiom.register_node(c, other, "foreign-doc", "document", 5, "verifier")
    assert {:error, :node_not_found} = Axiom.put_assignment(c, t, "alice", "reader", "foreign-doc", "active", 4, "verifier")
    assert {:error, :node_not_found} = Axiom.put_relation(c, t, "alice", "owner", "foreign-doc", "active", 4, "verifier")
    assert {:ok, _} = Axiom.save_draft(c, t, body("read"), 0)
    results = for _ <- 1..8 do Task.async(fn -> Axiom.publish(c, t, 1, 0, "same-request", "verifier") end) end |> Enum.map(&Task.await(&1, 10_000))
    assert Enum.all?(results, &match?({:ok, _}, &1))
    assert length(Enum.uniq(results)) == 1
    {:ok, first} = hd(results)
    id = first["policy_release_id"]
    assert [[1]] = Store.query(c, "SELECT count(*) FROM axiom_releases WHERE tenant_id=$1", [t])
    assert {:error, :idempotency_conflict} = Axiom.publish(c, t, 1, 0, "same-request", "other-actor")
    assert {:error, :release_not_found} = Axiom.snapshot(c, other, "alice", release_id: id)
    assert {:error, :release_not_found} = Axiom.rollback_policy(c, other, id, 0, "foreign-release", "verifier", "test")
    assert {:error, %Postgrex.Error{}} = Postgrex.query(c, "UPDATE axiom_tenants SET policy_release_id=$2 WHERE id=$1", [other, id])
    assert {:error, %Postgrex.Error{}} = Postgrex.query(c, "UPDATE axiom_releases SET actor='changed' WHERE tenant_id=$1 AND id=$2", [t, id])
    assert {:error, %Postgrex.Error{}} = Postgrex.query(c, "DELETE FROM axiom_releases WHERE tenant_id=$1 AND id=$2", [t, id])
    assert {:ok, _} = Axiom.save_draft(c, t, body("write"), 1)
    competing = for request <- ~w(race-one race-two) do Task.async(fn -> Axiom.publish(c, t, 2, 1, request, "verifier") end) end |> Enum.map(&Task.await(&1, 10_000))
    assert Enum.count(competing, &match?({:ok, _}, &1)) == 1
    assert Enum.count(competing, &(&1 == {:error, :conflict})) == 1
    assert {:ok, ^first} = Axiom.publish(c, t, 1, 0, "same-request", "verifier")
    assert {:ok, _} = Axiom.put_assignment(c, t, "alice", "reader", "doc", "active", 4, "verifier")
    assert {:ok, _} = Axiom.put_relation(c, t, "alice", "member", "team", "active", 5, "verifier")
    assert {:ok, _} = Axiom.put_assignment(c, t, "alice", "reader", "doc", "revoked", 6, "verifier")
    assert {:ok, _} = Axiom.put_relation(c, t, "alice", "member", "team", "revoked", 7, "verifier")
    assert {:ok, _} = Axiom.set_principal_status(c, t, "alice", "suspended", 8, "verifier")
    assert {:ok, _} = Axiom.rollback_policy(c, t, id, 2, "restore", "verifier", "policy only")
    {:ok, snap} = Axiom.snapshot(c, t, "alice", release_id: id)
    assert snap["data"]["policy"]["body"] == body("read")
    assert snap["data"]["principal_status"] == "suspended"
    assert snap["data"]["assignment_revision"] == 9
    assert [%{"status" => "revoked"}] = snap["data"]["assignments"]
    assert [%{"status" => "revoked"}] = snap["data"]["relations"]
    assert {:ok, %{"status" => "not_modified"}} = Axiom.snapshot(c, t, "alice", if_none_match: snap["etag"])
    # A real late FK error aborts a containing transaction without shared schema changes.
    assert {:error, :constraint} = Store.transaction(c, fn tx ->
      {:ok, _} = Axiom.set_principal_status(tx, t, "alice", "active", 9, "verifier")
      Store.query(tx, "INSERT INTO axiom_assignments(tenant_id,principal,role,scope,status) VALUES($1,'alice','reader','never-created','active')", [t])
    end)
    {:ok, after_failure} = Axiom.snapshot(c, t, "alice")
    assert after_failure == snap
    {:ok, _} = Axiom.save_draft(c, t, body("read"), 2)
    assert {:error, :constraint} = Store.transaction(c, fn tx ->
      {:ok, _} = Axiom.publish(tx, t, 3, 3, "late-failure", "verifier")
      Store.query(tx, "INSERT INTO axiom_assignments(tenant_id,principal,role,scope,status) VALUES($1,'alice','reader','never-created','active')", [t])
    end)
    assert [[2]] = Store.query(c, "SELECT count(*) FROM axiom_releases WHERE tenant_id=$1", [t])
    assert {:ok, _} = Axiom.publish(c, t, 3, 3, "late-failure", "verifier")
    # Atomic pairs deliberately interleave a delay; readers must never see one half.
    writer = Task.async(fn ->
      for n <- 1..20 do
        {:ok, _} = Store.transaction(c, fn tx ->
          {:ok, _} = Axiom.rollback_policy(tx, t, id, n + 3, "pair-#{n}", "verifier", "atomic pair")
          Process.sleep(2)
          {:ok, _} = Axiom.set_principal_status(tx, t, "alice", if(rem(n, 2) == 1, do: "active", else: "suspended"), n + 8, "verifier")
        end)
      end
    end)
    for _ <- 1..80 do
      {:ok, read} = Axiom.snapshot(c, t, "alice")
      data = read["data"]
      assert data["assignment_revision"] == data["policy_generation"] + 5
      assert data["principal_status"] == if(rem(data["policy_generation"], 2) == 0, do: "suspended", else: "active")
    end
    Task.await(writer, 20_000)
    # Two CAS writes with the same expected revision have exactly one winner.
    cas = for status <- ~w(active suspended) do Task.async(fn -> Axiom.set_principal_status(c, t, "alice", status, 29, "verifier") end) end |> Enum.map(&Task.await(&1, 10_000))
    assert Enum.count(cas, &match?({:ok, _}, &1)) == 1
    assert Enum.count(cas, &(&1 == {:error, :conflict})) == 1
    {:ok, history} = Axiom.history(c, t)
    IO.inspect(%{assignments: length(history["assignments"]), publications: length(history["publications"]), fixture: t}, label: "fixture final evidence")
    assert length(history["assignments"]) == 30
    assert length(history["publications"]) == 24
    IO.puts("PASS: SQL/tenant inputs, foreign roles/nodes/releases, DB FK and immutable rows, 8 identical retries, publication and assignment races, current facts on rollback/versioned reads, late failures, 80 atomic snapshot reads")
  end
end
GenServer.stop(c)
