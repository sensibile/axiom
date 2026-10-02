defmodule Axiom.ResourceScopeTest do
  use ExUnit.Case, async: false
  alias Axiom.{Scope, Store}

  defp scope(tenant, space \\ "knowledge", scenario \\ "live"),
    do: %{
      "tenant_id" => tenant,
      "space_id" => space,
      "scenario_id" => scenario,
      "local_id" => "same"
    }

  defp policy(action \\ "read"),
    do: %{
      "schema_version" => 1,
      "rules" => [
        %{
          "effect" => "allow",
          "role" => "reader",
          "resource_kind" => "document",
          "actions" => [action]
        }
      ]
    }

  defp fresh(c) do
    tenant = "scope" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    {:ok, _} = Axiom.create_tenant(c, tenant)
    {:ok, _} = Axiom.register_role(c, tenant, "reader", 0, "admin")
    {:ok, _} = Axiom.register_node(c, tenant, "alice", "person", 1, "admin")
    {:ok, _} = Axiom.register_resource_scope(c, scope(tenant), "document", 2, "admin")
    tenant
  end

  setup do
    c = Application.fetch_env!(:axiom, :test_conn)
    {:ok, conn: c, tenant: fresh(c), other: fresh(c)}
  end

  test "exact identity rejects missing, typed, noncanonical and physical fields without mutation",
       %{conn: c, tenant: t} do
    valid = scope(t)

    invalid = [
      nil,
      [],
      "scope",
      Map.delete(valid, "scenario_id"),
      Map.put(valid, "table_uuid", "x"),
      %{valid | "space_id" => "*"},
      %{valid | "tenant_id" => "Tenant"},
      %{valid | "local_id" => " a"},
      %{valid | "scenario_id" => nil},
      %{valid | "local_id" => 1},
      %{valid | "space_id" => <<255>>},
      %{valid | "local_id" => String.duplicate("a", 65)}
    ]

    {:ok, before} = Axiom.history(c, t)

    for bad <- invalid do
      refute Scope.valid?(bad)

      assert {:error, :invalid_scope} =
               Axiom.register_resource_scope(c, bad, "document", 3, "admin")

      assert {:error, :invalid_scope} =
               Axiom.put_resource_assignment(c, bad, "alice", "reader", "active", 3, "admin")

      assert {:error, :invalid_scope} = Axiom.resource_snapshot(c, bad, "alice")
    end

    assert {:ok, ^before} = Axiom.history(c, t)
    assert {:error, :invalid_options} = Axiom.resource_snapshot(c, valid, "alice", query_cut: 1)

    assert {:error, :invalid_options} =
             Axiom.resource_snapshot(c, valid, "alice", resource_scope: scope(t, "other"))

    assert {:error, :invalid_scope} =
             Axiom.snapshot(c, t, "alice", resource_scope: %{valid | "tenant_id" => "other"})
  end

  test "same local ID in tenant space and scenario never inherits assignments or relations", %{
    conn: c,
    tenant: t,
    other: other
  } do
    a = scope(t)
    b = scope(t, "second")
    fork = scope(t, "knowledge", "fork")
    {:ok, _} = Axiom.register_resource_scope(c, b, "document", 3, "admin")
    {:ok, _} = Axiom.register_resource_scope(c, fork, "document", 4, "admin")
    {:ok, _} = Axiom.put_resource_assignment(c, a, "alice", "reader", "active", 5, "admin")
    {:ok, _} = Axiom.put_resource_relation(c, a, "alice", "owner", "active", 6, "admin")
    {:ok, snap} = Axiom.resource_snapshot(c, a, "alice")

    assert snap["data"]["assignments"] == [
             %{"role" => "reader", "scope" => a, "status" => "active"}
           ]

    assert snap["data"]["relations"] == [
             %{"relation" => "owner", "object" => a, "status" => "active"}
           ]

    for empty <- [b, fork, scope(other)] do
      {:ok, result} = Axiom.resource_snapshot(c, empty, "alice")
      assert result["data"]["assignments"] == []
      assert result["data"]["relations"] == []
      refute result["etag"] == snap["etag"]
    end

    assert {:error, :scope_not_found} = Axiom.resource_snapshot(c, scope(t, "missing"), "alice")
  end

  test "internal key collision and duplicate registry fail atomically", %{conn: c, tenant: t} do
    a = scope(t, "collision")
    {:ok, _} = Axiom.register_node(c, t, Scope.node_key(a), "document", 3, "admin")
    {:ok, before} = Axiom.history(c, t)

    assert {:error, :scope_collision} =
             Axiom.register_resource_scope(c, a, "document", 4, "admin")

    assert {:error, :scope_collision} =
             Axiom.register_resource_scope(c, scope(t), "document", 4, "admin")

    assert {:ok, ^before} = Axiom.history(c, t)
    assert {:error, :scope_not_found} = Axiom.resource_snapshot(c, a, "alice")

    assert {:error, %Postgrex.Error{}} =
             Postgrex.query(
               c,
               "UPDATE axiom_resource_scopes SET local_id='changed' WHERE tenant_id=$1",
               [t]
             )
  end

  test "historical policy and rollback retain current revoked facts and suspended principal", %{
    conn: c,
    tenant: t
  } do
    a = scope(t)
    {:ok, _} = Axiom.save_draft(c, t, policy(), 0)
    {:ok, first} = Axiom.publish(c, t, 1, 0, "first", "admin")
    {:ok, _} = Axiom.save_draft(c, t, policy("write"), 1)
    {:ok, second} = Axiom.publish(c, t, 2, 1, "second", "admin")
    {:ok, _} = Axiom.put_resource_assignment(c, a, "alice", "reader", "active", 3, "admin")
    {:ok, _} = Axiom.put_resource_relation(c, a, "alice", "owner", "active", 4, "admin")
    {:ok, before} = Axiom.resource_snapshot(c, a, "alice", release_id: first["policy_release_id"])
    {:ok, _} = Axiom.put_resource_assignment(c, a, "alice", "reader", "revoked", 5, "admin")
    {:ok, _} = Axiom.put_resource_relation(c, a, "alice", "owner", "revoked", 6, "admin")
    {:ok, _} = Axiom.set_principal_status(c, t, "alice", "suspended", 7, "admin")

    {:ok, historical} =
      Axiom.resource_snapshot(c, a, "alice",
        release_id: first["policy_release_id"],
        if_none_match: before["etag"]
      )

    assert historical["status"] == "ok"
    assert historical["data"]["policy_head_release_id"] == second["policy_release_id"]
    assert historical["data"]["policy"]["release_id"] == first["policy_release_id"]

    {:ok, _} =
      Axiom.rollback_policy(
        c,
        t,
        first["policy_release_id"],
        2,
        "rollback",
        "admin",
        "policy only"
      )

    {:ok, result} = Axiom.resource_snapshot(c, a, "alice")
    assert result["data"]["assignment_revision"] == 8
    assert result["data"]["policy_generation"] == 3
    assert result["data"]["principal_status"] == "suspended"
    assert Enum.map(result["data"]["assignments"], & &1["status"]) == ["revoked"]
    assert Enum.map(result["data"]["relations"], & &1["status"]) == ["revoked"]
    assert result["data"]["consumer_contract"]["decision"] == "not_evaluated"
    assert result["data"]["consumer_contract"]["knowledge_cut"] == "external_not_verified"

    assert {:ok, %{"status" => "not_modified"}} =
             Axiom.resource_snapshot(c, a, "alice", if_none_match: result["etag"])

    assert {:error, :release_not_found} =
             Axiom.resource_snapshot(c, a, "alice", release_id: 9_223_372_036_854_775_807)
  end

  test "scoped CAS concurrency has one winner and unknown scope is mutation free", %{
    conn: c,
    tenant: t
  } do
    a = scope(t)
    {:ok, before} = Axiom.history(c, t)

    assert {:error, :scope_not_found} =
             Axiom.put_resource_assignment(
               c,
               scope(t, "missing"),
               "alice",
               "reader",
               "active",
               3,
               "admin"
             )

    assert {:error, :unknown_role} =
             Axiom.put_resource_assignment(c, a, "alice", "missing", "active", 3, "admin")

    assert {:ok, ^before} = Axiom.history(c, t)

    tasks =
      for _ <- 1..2,
          do:
            Task.async(fn ->
              Axiom.put_resource_assignment(c, a, "alice", "reader", "active", 3, "admin")
            end)

    results = Enum.map(tasks, &Task.await/1)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert {:error, :conflict} in results

    assert {:error, :conflict} =
             Axiom.put_resource_relation(c, a, "alice", "owner", "active", 3, "admin")
  end

  test "independent map oracle across scopes and current revisions", %{conn: c, tenant: t} do
    scopes = [scope(t), scope(t, "second"), scope(t, "knowledge", "fork")]
    {:ok, _} = Axiom.register_resource_scope(c, Enum.at(scopes, 1), "document", 3, "admin")
    {:ok, _} = Axiom.register_resource_scope(c, Enum.at(scopes, 2), "document", 4, "admin")

    Enum.reduce(1..60, {%{}, 5}, fn n, {model, revision} ->
      index = rem(n * 7, 3)
      selected = Enum.at(scopes, index)
      status = if rem(div(n, 3), 2) == 0, do: "active", else: "revoked"
      status = if Map.has_key?(model, index), do: status, else: "active"

      assert {:ok, %{"assignment_revision" => next}} =
               Axiom.put_resource_assignment(
                 c,
                 selected,
                 "alice",
                 "reader",
                 status,
                 revision,
                 "admin"
               )

      assert next == revision + 1
      model = Map.put(model, index, status)

      for {resource, i} <- Enum.with_index(scopes) do
        {:ok, result} = Axiom.resource_snapshot(c, resource, "alice")

        expected =
          case Map.fetch(model, i) do
            :error -> []
            {:ok, state} -> [%{"role" => "reader", "scope" => resource, "status" => state}]
          end

        assert result["data"]["assignments"] == expected
        assert result["data"]["assignment_revision"] == next
      end

      {model, next}
    end)
  end

  test "scoped repeatable snapshot never mixes paired current mutations", %{conn: c, tenant: t} do
    a = scope(t)
    {:ok, _} = Axiom.put_resource_assignment(c, a, "alice", "reader", "active", 3, "admin")

    writer =
      Task.async(fn ->
        for n <- 1..30 do
          revision = 4 + (n - 1) * 2
          assignment = if rem(n, 2) == 0, do: "active", else: "revoked"
          principal = if rem(n, 2) == 0, do: "active", else: "suspended"

          assert {:ok, _} =
                   Store.transaction(c, fn tx ->
                     {:ok, _} =
                       Axiom.put_resource_assignment(
                         tx,
                         a,
                         "alice",
                         "reader",
                         assignment,
                         revision,
                         "admin"
                       )

                     {:ok, _} =
                       Axiom.set_principal_status(
                         tx,
                         t,
                         "alice",
                         principal,
                         revision + 1,
                         "admin"
                       )
                   end)
        end
      end)

    for _ <- 1..90 do
      {:ok, result} = Axiom.resource_snapshot(c, a, "alice")
      data = result["data"]
      bundle = result["revision_bundle"]
      assert bundle["assignment_revision"] == data["assignment_revision"]
      assert bundle["principal_status"] == data["principal_status"]

      assert {:ok, conditional} =
               Axiom.resource_snapshot(c, a, "alice", if_revision_bundle: bundle)

      assert conditional["status"] in ["changed", "not_modified"]

      assert conditional["revision_bundle"]["assignment_revision"] >=
               bundle["assignment_revision"]

      n = div(data["assignment_revision"] - 4, 2)
      assert rem(data["assignment_revision"], 2) == 0
      assert data["principal_status"] == if(rem(n, 2) == 0, do: "active", else: "suspended")

      assert hd(data["assignments"])["status"] ==
               if(rem(n, 2) == 0, do: "active", else: "revoked")
    end

    Task.await(writer)
  end

  test "late audit failure rolls back registry node revision and allows retry", %{
    conn: c,
    tenant: t
  } do
    target = scope(t, "late")
    function = "scope_fail_" <> t
    # Tenant is a generated validated identifier; failure trigger belongs only to this fixture.
    Store.query(
      c,
      "CREATE FUNCTION #{function}() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.tenant_id='#{t}' AND NEW.kind='resource_scope_registered' THEN RAISE EXCEPTION 'injected' USING ERRCODE='23514'; END IF; RETURN NEW; END $$"
    )

    Store.query(
      c,
      "CREATE TRIGGER #{function} BEFORE INSERT ON axiom_assignment_events FOR EACH ROW EXECUTE FUNCTION #{function}()"
    )

    {:ok, before} = Axiom.history(c, t)

    try do
      for {code, category} <- [{"23514", :constraint}, {"XX000", :database}] do
        Store.query(
          c,
          "CREATE OR REPLACE FUNCTION #{function}() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.tenant_id='#{t}' AND NEW.kind='resource_scope_registered' THEN RAISE EXCEPTION 'injected' USING ERRCODE='#{code}'; END IF; RETURN NEW; END $$"
        )

        assert {:error, ^category} =
                 Axiom.register_resource_scope(c, target, "document", 3, "admin")

        assert {:ok, ^before} = Axiom.history(c, t)
        assert {:error, :scope_not_found} = Axiom.resource_snapshot(c, target, "alice")

        assert [[0]] =
                 Store.query(
                   c,
                   "SELECT count(*) FROM axiom_nodes WHERE tenant_id=$1 AND key=$2",
                   [t, Scope.node_key(target)]
                 )
      end
    after
      Store.query(c, "DROP TRIGGER #{function} ON axiom_assignment_events")
      Store.query(c, "DROP FUNCTION #{function}()")
    end

    assert {:ok, %{"assignment_revision" => 4}} =
             Axiom.register_resource_scope(c, target, "document", 3, "admin")
  end

  test "bigint exhaustion preserves scoped facts and remains queryable", %{conn: c, tenant: t} do
    max = 9_223_372_036_854_775_807
    a = scope(t)
    Store.query(c, "UPDATE axiom_tenants SET assignment_revision=$2 WHERE id=$1", [t, max - 1])

    assert {:ok, %{"assignment_revision" => ^max}} =
             Axiom.put_resource_assignment(c, a, "alice", "reader", "active", max - 1, "admin")

    assert {:error, :revision_exhausted} =
             Axiom.put_resource_assignment(c, a, "alice", "reader", "revoked", max, "admin")

    assert {:error, :revision_exhausted} =
             Axiom.register_resource_scope(c, scope(t, "overflow"), "document", max, "admin")

    assert {:error, :invalid_revision} =
             Axiom.put_resource_assignment(c, a, "alice", "reader", "revoked", max + 1, "admin")

    {:ok, result} = Axiom.resource_snapshot(c, a, "alice")
    assert result["data"]["assignment_revision"] == max
    assert hd(result["data"]["assignments"])["status"] == "active"
  end

  test "concurrent publication and scoped read bind immutable body to current head", %{
    conn: c,
    tenant: t
  } do
    a = scope(t)
    {:ok, _} = Axiom.save_draft(c, t, policy(), 0)
    {:ok, first} = Axiom.publish(c, t, 1, 0, "pfirst", "admin")

    writer =
      Task.async(fn ->
        for generation <- 2..21 do
          action = if rem(generation, 2) == 0, do: "write", else: "read"
          {:ok, _} = Axiom.save_draft(c, t, policy(action), generation - 1)

          {:ok, _} =
            Axiom.publish(
              c,
              t,
              generation,
              generation - 1,
              "p" <> Integer.to_string(generation),
              "admin"
            )
        end
      end)

    for _ <- 1..70 do
      {:ok, current} = Axiom.resource_snapshot(c, a, "alice")
      data = current["data"]
      assert data["policy_head_release_id"] == data["policy"]["release_id"]
      action = if rem(data["policy_generation"], 2) == 0, do: "write", else: "read"
      assert hd(data["policy"]["body"]["rules"])["actions"] == [action]

      {:ok, historical} =
        Axiom.resource_snapshot(c, a, "alice", release_id: first["policy_release_id"])

      assert historical["data"]["policy"]["body"] == policy()
      assert historical["data"]["assignment_revision"] == 3
    end

    Task.await(writer)
  end

  test "revision bundles bind exact query and detect committed changes and ABA", %{
    conn: c,
    tenant: t,
    other: other
  } do
    a = scope(t)
    {:ok, _} = Axiom.save_draft(c, t, policy(), 0)
    {:ok, first} = Axiom.publish(c, t, 1, 0, "bundlefirst", "admin")
    {:ok, original} = Axiom.resource_snapshot(c, a, "alice")
    bundle = original["revision_bundle"]
    assert bundle["assignment_revision"] == 3
    assert bundle["policy_generation"] == 1

    for _ <- 1..3 do
      assert {:ok, %{"status" => "not_modified", "revision_bundle" => ^bundle}} =
               Axiom.resource_snapshot(c, a, "alice", if_revision_bundle: bundle)
    end

    for bad <- [
          nil,
          [],
          Map.delete(bundle, "etag"),
          Map.put(bundle, "unknown", 1),
          Map.put(bundle, "assignment_revision", "3")
        ] do
      assert {:error, :invalid_revision_bundle} =
               Axiom.resource_snapshot(c, a, "alice", if_revision_bundle: bad)
    end

    assert {:error, :revision_bundle_binding_mismatch} =
             Axiom.resource_snapshot(c, scope(other), "alice", if_revision_bundle: bundle)

    {:ok, _} = Axiom.register_node(c, t, "bob", "person", 3, "admin")

    assert {:error, :revision_bundle_binding_mismatch} =
             Axiom.resource_snapshot(c, a, "bob", if_revision_bundle: bundle)

    assert {:error, :revision_bundle_binding_mismatch} =
             Axiom.resource_snapshot(c, a, "alice",
               release_id: first["policy_release_id"],
               if_revision_bundle: bundle
             )

    {:ok, initial} =
      Axiom.resource_snapshot(c, a, "alice", release_id: first["policy_release_id"])

    commands = [
      fn -> Axiom.put_resource_assignment(c, a, "alice", "reader", "active", 4, "admin") end,
      fn -> Axiom.put_resource_assignment(c, a, "alice", "reader", "revoked", 5, "admin") end,
      fn -> Axiom.set_principal_status(c, t, "alice", "suspended", 6, "admin") end,
      fn -> Axiom.put_resource_relation(c, a, "alice", "owner", "active", 7, "admin") end,
      fn -> Axiom.publish(c, t, 1, 1, "samebody", "admin") end,
      fn ->
        Axiom.rollback_policy(c, t, first["policy_release_id"], 2, "bundleback", "admin", "ABA")
      end
    ]

    Enum.reduce(commands, initial["revision_bundle"], fn command, previous ->
      assert {:ok, _} = command |> Task.async() |> Task.await()

      assert {:ok, %{"status" => "changed"} = result} =
               Axiom.resource_snapshot(c, a, "alice",
                 release_id: first["policy_release_id"],
                 if_revision_bundle: previous
               )

      assert result["revision_bundle"]["assignment_revision"] ==
               result["data"]["assignment_revision"]

      result["revision_bundle"]
    end)

    assert {:ok, %{"status" => "changed", "data" => data}} =
             Axiom.resource_snapshot(c, a, "alice", if_revision_bundle: bundle)

    assert data["policy_generation"] == 3
    assert data["policy_head_release_id"] == first["policy_release_id"]
    assert data["principal_status"] == "suspended"
    assert hd(data["assignments"])["status"] == "revoked"
  end

  test "no-op consumes revision and structurally valid scope tampering is rejected", %{
    conn: c,
    tenant: t
  } do
    a = scope(t)
    {:ok, before} = Axiom.resource_snapshot(c, a, "alice")
    bundle = before["revision_bundle"]
    tampered = Map.put(bundle, "resource_scope", scope(t, "second"))

    assert {:error, :revision_bundle_binding_mismatch} =
             Axiom.resource_snapshot(c, a, "alice", if_revision_bundle: tampered)

    assert {:error, :invalid_options} =
             Axiom.resource_snapshot(c, a, "alice",
               if_revision_bundle: bundle,
               if_none_match: before["etag"]
             )

    {:ok, _} = Axiom.set_principal_status(c, t, "alice", "active", 3, "admin")

    assert {:ok, %{"status" => "changed", "revision_bundle" => next}} =
             Axiom.resource_snapshot(c, a, "alice", if_revision_bundle: bundle)

    assert next["assignment_revision"] == 4
    assert next["principal_status"] == bundle["principal_status"]
  end

  test "bundle numeric fields reject float boolean and malformed representations", %{
    conn: c,
    tenant: t
  } do
    a = scope(t)
    {:ok, _} = Axiom.save_draft(c, t, policy(), 0)
    {:ok, published} = Axiom.publish(c, t, 1, 0, "numeric", "admin")
    {:ok, original} = Axiom.resource_snapshot(c, a, "alice")
    bundle = original["revision_bundle"]

    fields =
      ~w(bundle_schema_version data_schema_version assignment_revision policy_generation policy_release_id policy_head_release_id)

    for field <- fields,
        value <- [bundle[field] / 1, 1.5, true, false, "1", [], %{}, %{1 => 1}] do
      assert {:error, :invalid_revision_bundle} =
               Axiom.resource_snapshot(c, a, "alice",
                 if_revision_bundle: Map.put(bundle, field, value)
               )
    end

    assert {:ok, %{"status" => "not_modified"}} =
             Axiom.resource_snapshot(c, a, "alice", if_revision_bundle: bundle)

    assert {:ok, %{"status" => "not_modified"}} =
             Axiom.resource_snapshot(c, a, "alice", if_none_match: original["etag"])

    for value <- [published["policy_release_id"] / 1, true, false, [], %{}] do
      assert {:error, :invalid_release} =
               Axiom.resource_snapshot(c, a, "alice", release_id: value)
    end
  end
end
