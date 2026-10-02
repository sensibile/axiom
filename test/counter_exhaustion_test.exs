defmodule Axiom.CounterExhaustionTest do
  use ExUnit.Case, async: false
  alias Axiom.{Domain, Store}
  @max 9_223_372_036_854_775_807
  @last @max - 1

  defp body(action \\ "read") do
    %{
      "schema_version" => 1,
      "rules" => [
        %{
          "effect" => "allow",
          "role" => "reader",
          "actions" => [action],
          "resource_kind" => "document"
        }
      ]
    }
  end

  setup do
    c = Application.fetch_env!(:axiom, :test_conn)
    t = "exhaustion-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    {:ok, _} = Axiom.create_tenant(c, t)
    {:ok, _} = Axiom.register_role(c, t, "reader", 0, "audit")
    {:ok, _} = Axiom.register_node(c, t, "alice", "person", 1, "audit")
    {:ok, _} = Axiom.register_node(c, t, "doc", "document", 2, "audit")
    {:ok, _} = Axiom.register_node(c, t, "team", "team", 3, "audit")
    {:ok, c: c, t: t}
  end

  test "stored bigint domain and increment domain are distinct" do
    assert Domain.revision(@max)
    assert Domain.next_revision(@last) == {:ok, @max}
    assert Domain.next_revision(@max) == {:error, :revision_exhausted}

    for value <- [-1, nil, 1.0, @max + 1] do
      refute Domain.revision(value)
      assert Domain.next_revision(value) == {:error, :invalid_revision}
    end
  end

  test "terminal assignment revision is readable and rejects every mutation before IO", %{
    c: c,
    t: t
  } do
    Store.query(c, "UPDATE axiom_tenants SET assignment_revision=$2 WHERE id=$1", [t, @last])

    assert {:ok, %{"assignment_revision" => @max}} =
             Axiom.register_role(c, t, "edge", @last, "audit")

    {:ok, before} = Axiom.snapshot(c, t, "alice")
    {:ok, history} = Axiom.history(c, t)
    assert before["data"]["assignment_revision"] == @max
    assert {:error, :revision_exhausted} = Axiom.register_role(c, t, "later", @max, "audit")

    assert {:error, :revision_exhausted} =
             Axiom.register_node(c, t, "later", "person", @max, "audit")

    assert {:error, :revision_exhausted} =
             Axiom.put_assignment(c, t, "alice", "reader", "doc", "active", @max, "audit")

    assert {:error, :revision_exhausted} =
             Axiom.put_relation(c, t, "alice", "member", "team", "active", @max, "audit")

    assert {:error, :revision_exhausted} =
             Axiom.set_principal_status(c, t, "alice", "suspended", @max, "audit")

    assert {:ok, ^before} = Axiom.snapshot(c, t, "alice")
    assert {:ok, ^history} = Axiom.history(c, t)

    assert [] ==
             Store.query(c, "SELECT key FROM axiom_roles WHERE tenant_id=$1 AND key='later'", [t])

    # Exhausting assignments cannot prevent independent policy changes.
    assert {:ok, _} = Axiom.save_draft(c, t, body(), 0)
    assert {:ok, _} = Axiom.publish(c, t, 1, 0, "independent", "audit")
  end

  test "terminal draft is publishable and failed edit preserves body and revision", %{c: c, t: t} do
    {:ok, _} = Axiom.save_draft(c, t, body(), 0)
    Store.query(c, "UPDATE axiom_drafts SET revision=$2 WHERE tenant_id=$1", [t, @last])
    assert {:ok, %{"draft_revision" => @max}} = Axiom.save_draft(c, t, body("write"), @last)
    {:ok, before} = Axiom.draft(c, t)
    assert {:error, :revision_exhausted} = Axiom.save_draft(c, t, body(), @max)
    assert {:ok, ^before} = Axiom.draft(c, t)
    assert {:ok, published} = Axiom.publish(c, t, @max, 0, "terminal-draft", "audit")
    assert {:ok, ^published} = Axiom.publish(c, t, @max, 0, "terminal-draft", "audit")
    {:ok, snap} = Axiom.snapshot(c, t, "alice", release_id: published["policy_release_id"])
    assert snap["data"]["policy"]["body"] == body("write")
  end

  test "terminal publication keeps exact retry and atomically refuses publish and rollback", %{
    c: c,
    t: t
  } do
    {:ok, _} = Axiom.save_draft(c, t, body(), 0)
    Store.query(c, "UPDATE axiom_tenants SET policy_generation=$2 WHERE id=$1", [t, @last])
    assert {:ok, published} = Axiom.publish(c, t, 1, @last, "last-publish", "audit")
    assert published["policy_generation"] == @max
    assert {:ok, ^published} = Axiom.publish(c, t, 1, @last, "last-publish", "audit")
    {:ok, before} = Axiom.snapshot(c, t, "alice")
    {:ok, history} = Axiom.history(c, t)
    assert {:error, :revision_exhausted} = Axiom.publish(c, t, 1, @max, "overflow", "audit")

    assert {:error, :revision_exhausted} =
             Axiom.rollback_policy(
               c,
               t,
               published["policy_release_id"],
               @max,
               "overflow-rollback",
               "audit",
               "stop"
             )

    assert {:ok, ^before} = Axiom.snapshot(c, t, "alice")
    assert {:ok, ^history} = Axiom.history(c, t)
    assert [[1]] = Store.query(c, "SELECT count(*) FROM axiom_releases WHERE tenant_id=$1", [t])

    assert [] ==
             Store.query(
               c,
               "SELECT request_id FROM axiom_publications WHERE tenant_id=$1 AND request_id='overflow'",
               [t]
             )

    assert {:error, :idempotency_conflict} = Axiom.publish(c, t, 1, @max, "last-publish", "audit")
    assert {:error, :invalid_revision} = Axiom.publish(c, t, 1, @max + 1, "invalid", "audit")
    assert {:ok, _} = Axiom.set_principal_status(c, t, "alice", "suspended", 4, "audit")
  end

  test "rollback can finish at max and concurrent final assignment has one winner", %{c: c, t: t} do
    {:ok, _} = Axiom.save_draft(c, t, body(), 0)
    {:ok, first} = Axiom.publish(c, t, 1, 0, "first", "audit")

    Store.query(
      c,
      "UPDATE axiom_tenants SET policy_generation=$2,assignment_revision=$2 WHERE id=$1",
      [t, @last]
    )

    assert {:ok, rolled} =
             Axiom.rollback_policy(
               c,
               t,
               first["policy_release_id"],
               @last,
               "last-rollback",
               "audit",
               "terminal"
             )

    assert rolled["policy_generation"] == @max

    assert {:ok, ^rolled} =
             Axiom.rollback_policy(
               c,
               t,
               first["policy_release_id"],
               @last,
               "last-rollback",
               "audit",
               "terminal"
             )

    tasks =
      for status <- ["active", "suspended"],
          do:
            Task.async(fn ->
              Axiom.set_principal_status(c, t, "alice", status, @last, "audit")
            end)

    results = Enum.map(tasks, &Task.await/1)
    assert Enum.count(results, &(&1 == {:ok, %{"assignment_revision" => @max}})) == 1
    assert Enum.count(results, &(&1 == {:error, :conflict})) == 1
    {:ok, snap} = Axiom.snapshot(c, t, "alice")
    assert snap["data"]["assignment_revision"] == @max
    assert snap["data"]["policy_generation"] == @max

    assert {:error, :revision_exhausted} =
             Axiom.set_principal_status(c, t, "alice", "active", @max, "audit")
  end
end
