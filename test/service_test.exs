defmodule Axiom.ServiceTest do
  use ExUnit.Case, async: false
  alias Axiom.Store

  defp policy(actions \\ ["read"]),
    do: %{
      "schema_version" => 1,
      "rules" => [
        %{
          "effect" => "allow",
          "role" => "reader",
          "resource_kind" => "document",
          "actions" => actions
        }
      ]
    }

  defp fresh(conn) do
    tenant = "t" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    {:ok, _} = Axiom.create_tenant(conn, tenant)
    {:ok, _} = Axiom.register_role(conn, tenant, "reader", 0, "admin")
    {:ok, _} = Axiom.register_node(conn, tenant, "alice", "person", 1, "admin")
    {:ok, _} = Axiom.register_node(conn, tenant, "doc", "document", 2, "admin")
    {:ok, _} = Axiom.register_node(conn, tenant, "team", "team", 3, "admin")
    tenant
  end

  setup do
    conn = Application.fetch_env!(:axiom, :test_conn)
    {:ok, conn: conn, tenant: fresh(conn), other: fresh(conn)}
  end

  test "draft validation, conflict, immutable publication and exact retry", %{conn: c, tenant: t} do
    assert {:error, :unknown_role} =
             Axiom.save_draft(
               c,
               t,
               put_in(policy(), ["rules", Access.at(0), "role"], "missing"),
               0
             )

    assert {:error, :invalid_policy} =
             Axiom.save_draft(c, t, Map.put(policy(), "code", "eval"), 0)

    assert {:error, :draft_not_found} = Axiom.draft(c, t)
    assert {:ok, %{"draft_revision" => 1}} = Axiom.save_draft(c, t, policy(), 0)
    assert {:error, :conflict} = Axiom.save_draft(c, t, policy(), 0)
    assert {:error, :conflict} = Axiom.publish(c, t, 2, 0, "pubbad", "admin")
    assert {:ok, result} = Axiom.publish(c, t, 1, 0, "pubone", "admin")
    assert {:ok, ^result} = Axiom.publish(c, t, 1, 0, "pubone", "admin")
    assert {:error, :idempotency_conflict} = Axiom.publish(c, t, 1, 1, "pubone", "admin")
    assert [[1]] = Store.query(c, "SELECT count(*) FROM axiom_releases WHERE tenant_id=$1", [t])
    id = result["policy_release_id"]

    assert {:error, %Postgrex.Error{}} =
             Postgrex.query(
               c,
               "UPDATE axiom_releases SET actor='evil' WHERE tenant_id=$1 AND id=$2",
               [t, id]
             )

    assert {:error, %Postgrex.Error{}} =
             Postgrex.query(c, "DELETE FROM axiom_releases WHERE tenant_id=$1 AND id=$2", [t, id])

    assert {:ok, snap} = Axiom.snapshot(c, t, "alice")
    assert snap["data"]["policy"]["body"] == policy()

    assert {:ok, %{"status" => "not_modified"}} =
             Axiom.snapshot(c, t, "alice", if_none_match: snap["etag"])
  end

  test "independent assignments, revocation and suspension survive policy rollback", %{
    conn: c,
    tenant: t
  } do
    {:ok, _} = Axiom.save_draft(c, t, policy(["read", "write"]), 0)
    {:ok, first} = Axiom.publish(c, t, 1, 0, "first", "admin")
    {:ok, _} = Axiom.save_draft(c, t, policy(), 1)
    {:ok, _} = Axiom.publish(c, t, 2, 1, "second", "admin")

    assert {:ok, %{"assignment_revision" => 5}} =
             Axiom.put_assignment(c, t, "alice", "reader", "doc", "active", 4, "admin")

    {:ok, _} = Axiom.put_relation(c, t, "alice", "member", "team", "active", 5, "admin")
    {:ok, before} = Axiom.snapshot(c, t, "alice")
    assert before["data"]["policy_generation"] == 2
    {:ok, _} = Axiom.put_assignment(c, t, "alice", "reader", "doc", "revoked", 6, "admin")
    {:ok, _} = Axiom.put_relation(c, t, "alice", "member", "team", "revoked", 7, "admin")
    {:ok, _} = Axiom.set_principal_status(c, t, "alice", "suspended", 8, "admin")

    {:ok, rolled} =
      Axiom.rollback_policy(
        c,
        t,
        first["policy_release_id"],
        2,
        "rollback",
        "admin",
        "restore policy only"
      )

    assert rolled["policy_generation"] == 3
    {:ok, after_snapshot} = Axiom.snapshot(c, t, "alice")
    data = after_snapshot["data"]
    assert data["assignment_revision"] == 9
    assert data["principal_status"] == "suspended"
    assert [%{"status" => "revoked"}] = data["assignments"]
    assert [%{"status" => "revoked"}] = data["relations"]
    assert data["policy"]["body"] == policy(["read", "write"])
    refute before["etag"] == after_snapshot["etag"]
    {:ok, history} = Axiom.history(c, t)
    assert length(history["assignments"]) == 9
    assert length(history["publications"]) == 3
  end

  test "fixed policy version uses current assignments and forbids cross tenant release", %{
    conn: c,
    tenant: t,
    other: other
  } do
    {:ok, _} = Axiom.save_draft(c, t, policy(), 0)
    {:ok, one} = Axiom.publish(c, t, 1, 0, "one", "admin")
    {:ok, _} = Axiom.save_draft(c, t, policy(["write"]), 1)
    {:ok, _} = Axiom.publish(c, t, 2, 1, "two", "admin")
    {:ok, _} = Axiom.put_assignment(c, t, "alice", "reader", "doc", "active", 4, "admin")
    {:ok, snap} = Axiom.snapshot(c, t, "alice", release_id: one["policy_release_id"])
    assert snap["data"]["policy"]["body"] == policy()
    assert snap["data"]["assignment_revision"] == 5

    assert {:error, :release_not_found} =
             Axiom.snapshot(c, other, "alice", release_id: one["policy_release_id"])

    assert {:error, :release_not_found} =
             Axiom.rollback_policy(
               c,
               other,
               one["policy_release_id"],
               0,
               "foreign",
               "admin",
               "no"
             )

    {:ok, _} = Axiom.register_node(c, other, "only-other", "document", 4, "admin")

    assert {:error, :node_not_found} =
             Axiom.put_assignment(c, t, "alice", "reader", "only-other", "active", 5, "admin")

    assert {:error, %Postgrex.Error{}} =
             Postgrex.query(c, "UPDATE axiom_tenants SET policy_release_id=$2 WHERE id=$1", [
               other,
               one["policy_release_id"]
             ])

    assert {:error, %Postgrex.Error{}} =
             Postgrex.query(
               c,
               "INSERT INTO axiom_assignments(tenant_id,principal,role,scope,status) VALUES($1,'alice','reader','only-other','active')",
               [t]
             )
  end

  test "invalid input and stale assignment revisions leave no partial history", %{
    conn: c,
    tenant: t
  } do
    assert {:error, :invalid_identifier} = Axiom.register_role(c, t, "x';drop", 4, "admin")
    assert {:error, :invalid_revision} = Axiom.register_role(c, t, "valid", nil, "admin")

    assert {:error, :invalid_revision} =
             Axiom.register_role(c, t, "valid", 9_223_372_036_854_775_808, "admin")

    assert {:error, :invalid_release} =
             Axiom.snapshot(c, t, "alice", release_id: 9_223_372_036_854_775_808)

    assert {:error, :invalid_argument} =
             Axiom.rollback_policy(c, t, 1, 0, "bad-utf8", "admin", <<255>>)

    assert {:error, :invalid_relation} =
             Axiom.put_relation(c, t, "alice", "member", "doc", "active", 4, "admin")

    assert {:error, :conflict} =
             Axiom.set_principal_status(c, t, "alice", "suspended", 3, "admin")

    assert {:error, :invalid_status} =
             Axiom.put_assignment(c, t, "alice", "reader", "doc", "anything", 4, "admin")

    {:ok, snap} = Axiom.snapshot(c, t, "alice")
    assert snap["data"]["assignment_revision"] == 4
    {:ok, h} = Axiom.history(c, t)
    assert length(h["assignments"]) == 4
    assert {:error, :tenant_not_found} = Axiom.snapshot(c, "not-present", "alice")
  end

  test "concurrent publication and assignment CAS have one winner", %{conn: c, tenant: t} do
    {:ok, _} = Axiom.save_draft(c, t, policy(), 0)

    results =
      for req <- ["race-a", "race-b"] do
        Task.async(fn -> Axiom.publish(c, t, 1, 0, req, "admin") end)
      end
      |> Enum.map(&Task.await/1)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :conflict})) == 1

    writes =
      for status <- ["active", "suspended"] do
        Task.async(fn -> Axiom.set_principal_status(c, t, "alice", status, 4, "admin") end)
      end
      |> Enum.map(&Task.await/1)

    assert Enum.count(writes, &match?({:ok, _}, &1)) == 1
    assert Enum.count(writes, &(&1 == {:error, :conflict})) == 1
  end

  test "repeatable read pins old head and facts while writers commit", %{conn: c, tenant: t} do
    {:ok, _} = Axiom.save_draft(c, t, policy(), 0)
    {:ok, first} = Axiom.publish(c, t, 1, 0, "old", "admin")
    parent = self()

    reader =
      Task.async(fn ->
        Store.transaction(
          c,
          fn tx ->
            old = Store.tenant!(tx, t)
            send(parent, {:pinned, self()})

            receive do
              :continue -> :ok
            after
              5000 -> flunk("writer timeout")
            end

            # Service runs inside this already pinned transaction; sees its snapshot.
            {:ok, snapshot} = Axiom.snapshot(tx, t, "alice")
            assert Store.tenant!(tx, t) == old
            snapshot
          end,
          :read
        )
      end)

    assert_receive {:pinned, pid}, 5000
    {:ok, _} = Axiom.save_draft(c, t, policy(["write"]), 1)
    {:ok, _} = Axiom.publish(c, t, 2, 1, "new", "admin")
    {:ok, _} = Axiom.set_principal_status(c, t, "alice", "suspended", 4, "admin")
    send(pid, :continue)
    {:ok, pinned} = Task.await(reader)
    assert pinned["data"]["policy"]["release_id"] == first["policy_release_id"]
    assert pinned["data"]["assignment_revision"] == 4
    assert pinned["data"]["principal_status"] == "active"
    {:ok, current} = Axiom.snapshot(c, t, "alice")
    assert current["data"]["assignment_revision"] == 5
    assert current["data"]["principal_status"] == "suspended"
    refute current["data"]["policy"]["release_id"] == first["policy_release_id"]
  end

  test "service snapshot cannot mix halves of concurrent committed writes", %{conn: c, tenant: t} do
    {:ok, _} = Axiom.save_draft(c, t, policy(), 0)
    {:ok, release} = Axiom.publish(c, t, 1, 0, "base", "admin")
    parent = self()

    writer =
      Task.async(fn ->
        send(parent, :writer_ready)
        receive do: (:go -> :ok)

        for generation <- 1..40 do
          {:ok, _} =
            Store.transaction(c, fn tx ->
              {:ok, _} =
                Axiom.rollback_policy(
                  tx,
                  t,
                  release["policy_release_id"],
                  generation,
                  "pair-#{generation}",
                  "admin",
                  "test atomic pair"
                )

              Process.sleep(1)
              status = if rem(generation + 1, 2) == 0, do: "suspended", else: "active"

              {:ok, _} =
                Axiom.set_principal_status(tx, t, "alice", status, generation + 3, "admin")
            end)
        end
      end)

    assert_receive :writer_ready
    send(writer.pid, :go)

    for _ <- 1..80 do
      {:ok, snapshot} = Axiom.snapshot(c, t, "alice")
      data = snapshot["data"]
      assert data["assignment_revision"] == data["policy_generation"] + 3
      expected = if rem(data["policy_generation"], 2) == 0, do: "suspended", else: "active"
      assert data["principal_status"] == expected
    end

    Task.await(writer, 10_000)
    {:ok, last} = Axiom.snapshot(c, t, "alice")
    assert last["data"]["policy_generation"] == 41
    assert last["data"]["assignment_revision"] == 44
  end

  test "real SQL late failures roll back both mutation kinds", %{conn: c, tenant: t} do
    # Only this dedicated DB: inject late failure via tenant-specific audit triggers.
    Store.query(
      c,
      "CREATE OR REPLACE FUNCTION axiom_test_fault() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.actor='inject-failure' THEN RAISE EXCEPTION 'injected late failure' USING ERRCODE='23514'; END IF; RETURN NEW; END $$"
    )

    Store.query(
      c,
      "CREATE TRIGGER axiom_test_assignment_fault BEFORE INSERT ON axiom_assignment_events FOR EACH ROW EXECUTE FUNCTION axiom_test_fault()"
    )

    Store.query(
      c,
      "CREATE TRIGGER axiom_test_publication_fault BEFORE INSERT ON axiom_publications FOR EACH ROW EXECUTE FUNCTION axiom_test_fault()"
    )

    try do
      assert {:error, :constraint} =
               Axiom.set_principal_status(c, t, "alice", "suspended", 4, "inject-failure")

      {:ok, _} = Axiom.save_draft(c, t, policy(), 0)
      assert {:error, :constraint} = Axiom.publish(c, t, 1, 0, "fault", "inject-failure")
      {:ok, snap} = Axiom.snapshot(c, t, "alice")
      assert snap["data"]["principal_status"] == "active"
      assert snap["data"]["assignment_revision"] == 4
      assert snap["data"]["policy"] == nil
      assert snap["data"]["policy_generation"] == 0
      assert [[0]] = Store.query(c, "SELECT count(*) FROM axiom_releases WHERE tenant_id=$1", [t])
      assert {:ok, _} = Axiom.publish(c, t, 1, 0, "fault", "admin")
    after
      Store.query(c, "DROP TRIGGER axiom_test_assignment_fault ON axiom_assignment_events")
      Store.query(c, "DROP TRIGGER axiom_test_publication_fault ON axiom_publications")
      Store.query(c, "DROP FUNCTION axiom_test_fault()")
    end
  end
end
