defmodule Axiom do
  @moduledoc "Trusted local PAP/PRP service boundary. Does not issue tokens or evaluate permissions."
  alias Axiom.{Domain, Scope, Store}

  def create_tenant(conn, tenant) do
    Store.transaction(conn, fn tx ->
      Store.valid!(tx, [tenant])
      Store.query(tx, "INSERT INTO axiom_tenants(id) VALUES($1) ON CONFLICT DO NOTHING", [tenant])
      %{"tenant_id" => tenant}
    end)
  end

  def register_role(conn, tenant, role, expected_revision, actor) do
    change(conn, tenant, expected_revision, actor, fn tx ->
      Store.valid!(tx, [role])

      Store.require!(
        tx,
        Store.query(tx, "SELECT key FROM axiom_roles WHERE tenant_id=$1 AND key=$2", [
          tenant,
          role
        ]) == [],
        :already_exists
      )

      Store.query(tx, "INSERT INTO axiom_roles(tenant_id,key) VALUES($1,$2)", [tenant, role])
      {"role_registered", %{"role" => role}}
    end)
  end

  def register_node(conn, tenant, key, kind, expected_revision, actor) do
    change(conn, tenant, expected_revision, actor, fn tx ->
      Store.valid!(tx, [key])
      Store.require!(tx, Domain.kind(kind), :invalid_kind)

      Store.require!(
        tx,
        Store.query(tx, "SELECT key FROM axiom_nodes WHERE tenant_id=$1 AND key=$2", [tenant, key]) ==
          [],
        :already_exists
      )

      Store.query(
        tx,
        "INSERT INTO axiom_nodes(tenant_id,key,kind,status) VALUES($1,$2,$3,'active')",
        [tenant, key, kind]
      )

      {"node_registered", %{"key" => key, "kind" => kind}}
    end)
  end

  def register_resource_scope(conn, scope, kind, expected_revision, actor) do
    if Scope.valid?(scope) do
      change(conn, scope["tenant_id"], expected_revision, actor, fn tx ->
        Store.require!(tx, Domain.resource_kind(kind), :invalid_resource_kind)
        key = Scope.node_key(scope)
        tenant = scope["tenant_id"]

        Store.require!(
          tx,
          Store.query(tx, "SELECT key FROM axiom_nodes WHERE tenant_id=$1 AND key=$2", [
            tenant,
            key
          ]) == [],
          :scope_collision
        )

        Store.query(
          tx,
          "INSERT INTO axiom_nodes(tenant_id,key,kind,status) VALUES($1,$2,$3,'active')",
          [tenant, key, kind]
        )

        Store.query(
          tx,
          "INSERT INTO axiom_resource_scopes(tenant_id,space_id,scenario_id,local_id,node_key) VALUES($1,$2,$3,$4,$5)",
          [tenant, scope["space_id"], scope["scenario_id"], scope["local_id"], key]
        )

        {"resource_scope_registered", %{"resource_scope" => scope, "kind" => kind}}
      end)
    else
      {:error, :invalid_scope}
    end
  end

  def put_resource_assignment(conn, scope, principal, role, status, revision, actor) do
    scoped_change(conn, scope, fn tx, tenant, key ->
      put_assignment(tx, tenant, principal, role, key, status, revision, actor)
    end)
  end

  def put_resource_relation(conn, scope, principal, relation, status, revision, actor) do
    scoped_change(conn, scope, fn tx, tenant, key ->
      put_relation(tx, tenant, principal, relation, key, status, revision, actor)
    end)
  end

  defp scoped_change(conn, scope, fun) do
    Store.transaction(conn, fn tx ->
      key = Store.resource_scope!(tx, scope)

      case fun.(tx, scope["tenant_id"], key) do
        {:ok, result} -> result
        {:error, reason} -> Postgrex.rollback(tx, reason)
      end
    end)
  end

  def resource_snapshot(conn, scope, principal, opts \\ []) do
    cond do
      not Scope.valid?(scope) ->
        {:error, :invalid_scope}

      not is_list(opts) or not Keyword.keyword?(opts) ->
        {:error, :invalid_options}

      length(Keyword.keys(opts)) != length(Enum.uniq(Keyword.keys(opts))) or
          Enum.any?(
            Keyword.keys(opts),
            &(&1 not in [:release_id, :if_none_match, :if_revision_bundle])
          ) ->
        {:error, :invalid_options}

      Keyword.has_key?(opts, :if_revision_bundle) and Keyword.has_key?(opts, :if_none_match) ->
        {:error, :invalid_options}

      true ->
        snapshot(conn, scope["tenant_id"], principal, Keyword.put(opts, :resource_scope, scope))
    end
  end

  def put_assignment(conn, tenant, principal, role, scope, status, expected_revision, actor) do
    change(conn, tenant, expected_revision, actor, fn tx ->
      Store.valid!(tx, [principal, role, scope])
      Store.require!(tx, Domain.assignment_status(status), :invalid_status)
      {kind, _} = Store.node!(tx, tenant, principal)
      {scope_kind, _} = Store.node!(tx, tenant, scope)

      Store.require!(
        tx,
        Domain.principal_kind(kind) and Domain.resource_kind(scope_kind),
        :invalid_assignment
      )

      Store.require!(tx, role in Store.role_keys(tx, tenant), :unknown_role)

      previous =
        Store.query(
          tx,
          "SELECT status FROM axiom_assignments WHERE tenant_id=$1 AND principal=$2 AND role=$3 AND scope=$4",
          [tenant, principal, role, scope]
        )

      Store.require!(tx, status != "revoked" or previous != [], :assignment_not_found)

      Store.query(
        tx,
        "INSERT INTO axiom_assignments(tenant_id,principal,role,scope,status) VALUES($1,$2,$3,$4,$5) ON CONFLICT(tenant_id,principal,role,scope) DO UPDATE SET status=EXCLUDED.status",
        [tenant, principal, role, scope, status]
      )

      {"assignment_changed",
       %{
         "principal" => principal,
         "role" => role,
         "scope" => scope,
         "before" => List.flatten(previous),
         "after" => status
       }}
    end)
  end

  def put_relation(conn, tenant, subject, relation, object, status, expected_revision, actor) do
    change(conn, tenant, expected_revision, actor, fn tx ->
      Store.valid!(tx, [subject, object])
      Store.require!(tx, Domain.assignment_status(status), :invalid_status)
      {subject_kind, _} = Store.node!(tx, tenant, subject)
      {object_kind, _} = Store.node!(tx, tenant, object)
      Store.require!(tx, Domain.relation(subject_kind, relation, object_kind), :invalid_relation)

      previous =
        Store.query(
          tx,
          "SELECT status FROM axiom_relations WHERE tenant_id=$1 AND subject=$2 AND relation=$3 AND object=$4",
          [tenant, subject, relation, object]
        )

      Store.require!(tx, status != "revoked" or previous != [], :relation_not_found)

      Store.query(
        tx,
        "INSERT INTO axiom_relations(tenant_id,subject,relation,object,status) VALUES($1,$2,$3,$4,$5) ON CONFLICT(tenant_id,subject,relation,object) DO UPDATE SET status=EXCLUDED.status",
        [tenant, subject, relation, object, status]
      )

      {"relation_changed",
       %{
         "subject" => subject,
         "relation" => relation,
         "object" => object,
         "before" => List.flatten(previous),
         "after" => status
       }}
    end)
  end

  def set_principal_status(conn, tenant, principal, status, expected_revision, actor) do
    change(conn, tenant, expected_revision, actor, fn tx ->
      Store.valid!(tx, [principal])
      Store.require!(tx, Domain.status(status), :invalid_status)
      {kind, before} = Store.node!(tx, tenant, principal)
      Store.require!(tx, Domain.principal_kind(kind), :invalid_principal)

      Store.query(tx, "UPDATE axiom_nodes SET status=$3 WHERE tenant_id=$1 AND key=$2", [
        tenant,
        principal,
        status
      ])

      {"principal_status_changed",
       %{"principal" => principal, "before" => before, "after" => status}}
    end)
  end

  defp change(conn, tenant, revision, actor, fun) do
    Store.transaction(conn, fn tx ->
      Store.valid!(tx, [actor])
      Store.require!(tx, Domain.revision(revision), :invalid_revision)
      state = Store.tenant!(tx, tenant, true)
      Store.require!(tx, state.assignment_revision == revision, :conflict)
      next = Store.next_revision!(tx, state.assignment_revision)
      {kind, payload} = fun.(tx)
      Store.bump!(tx, tenant, kind, payload, actor, next)
    end)
  end

  def save_draft(conn, tenant, body, expected_revision) do
    Store.transaction(conn, fn tx ->
      Store.tenant!(tx, tenant, true)
      Store.require!(tx, Domain.revision(expected_revision), :invalid_revision)
      draft = Store.query(tx, "SELECT revision FROM axiom_drafts WHERE tenant_id=$1", [tenant])

      current =
        case draft do
          [] -> 0
          [[r]] -> r
        end

      Store.require!(tx, current == expected_revision, :conflict)
      next = Store.next_revision!(tx, current)

      case Domain.policy(body, Store.role_keys(tx, tenant)) do
        {:error, reason} ->
          Postgrex.rollback(tx, reason)

        {:ok, validated} ->
          Store.query(
            tx,
            "INSERT INTO axiom_drafts(tenant_id,revision,body) VALUES($1,$2,$3) ON CONFLICT(tenant_id) DO UPDATE SET revision=EXCLUDED.revision,body=EXCLUDED.body",
            [tenant, next, validated]
          )

          %{"draft_revision" => next}
      end
    end)
  end

  def draft(conn, tenant) do
    Store.transaction(
      conn,
      fn tx ->
        Store.tenant!(tx, tenant)

        case Store.query(tx, "SELECT revision,body FROM axiom_drafts WHERE tenant_id=$1", [tenant]) do
          [[revision, body]] -> %{"draft_revision" => revision, "body" => body}
          [] -> Postgrex.rollback(tx, :draft_not_found)
        end
      end,
      :read
    )
  end

  def publish(conn, tenant, draft_revision, expected_generation, request_id, actor) do
    publication(
      conn,
      tenant,
      expected_generation,
      request_id,
      actor,
      "publish",
      %{"draft_revision" => draft_revision},
      fn tx, _state ->
        Store.require!(
          tx,
          Domain.revision(draft_revision) and draft_revision > 0,
          :invalid_revision
        )

        case Store.query(tx, "SELECT revision,body FROM axiom_drafts WHERE tenant_id=$1", [tenant]) do
          [[^draft_revision, body]] ->
            publish_release(tx, tenant, draft_revision, body, actor)

          [] ->
            Postgrex.rollback(tx, :draft_not_found)

          _ ->
            Postgrex.rollback(tx, :conflict)
        end
      end
    )
  end

  defp publish_release(tx, tenant, draft_revision, body, actor) do
    case Domain.policy(body, Store.role_keys(tx, tenant)) do
      {:error, reason} ->
        Postgrex.rollback(tx, reason)

      {:ok, body} ->
        [[id]] =
          Store.query(
            tx,
            "INSERT INTO axiom_releases(tenant_id,draft_revision,body,digest,actor) VALUES($1,$2,$3,$4,$5) RETURNING id",
            [tenant, draft_revision, body, Domain.digest(body), actor]
          )

        {id, "policy published"}
    end
  end

  def rollback_policy(conn, tenant, release_id, expected_generation, request_id, actor, reason) do
    publication(
      conn,
      tenant,
      expected_generation,
      request_id,
      actor,
      "rollback",
      %{"release_id" => release_id, "reason" => reason},
      fn tx, _state ->
        Store.require!(tx, is_integer(release_id) and release_id > 0, :invalid_release)
        Store.require!(tx, is_binary(reason) and byte_size(reason) in 1..512, :invalid_reason)

        Store.require!(
          tx,
          Store.query(tx, "SELECT id FROM axiom_releases WHERE tenant_id=$1 AND id=$2", [
            tenant,
            release_id
          ]) != [],
          :release_not_found
        )

        {release_id, reason}
      end
    )
  end

  defp publication(conn, tenant, generation, request_id, actor, kind, args, fun) do
    Store.transaction(conn, fn tx ->
      Store.valid!(tx, [request_id, actor])
      Store.require!(tx, Domain.revision(generation), :invalid_revision)
      state = Store.tenant!(tx, tenant, true)
      # Restrict publication arguments before canonicalizing arbitrary external values.
      Store.require!(
        tx,
        Enum.all?(Map.values(args), fn value ->
          Domain.revision(value) or
            (is_binary(value) and byte_size(value) <= 512 and String.valid?(value))
        end),
        :invalid_argument
      )

      fingerprint =
        Domain.digest(%{
          "kind" => kind,
          "args" => args,
          "generation" => generation,
          "actor" => actor
        })

      case Store.query(
             tx,
             "SELECT fingerprint,result FROM axiom_publications WHERE tenant_id=$1 AND request_id=$2",
             [tenant, request_id]
           ) do
        [[^fingerprint, result]] ->
          result

        [[_, _]] ->
          Postgrex.rollback(tx, :idempotency_conflict)

        [] ->
          Store.require!(tx, state.generation == generation, :conflict)
          next = Store.next_revision!(tx, state.generation)
          {release, reason} = fun.(tx, state)
          result = %{"policy_release_id" => release, "policy_generation" => next, "kind" => kind}

          Store.query(
            tx,
            "UPDATE axiom_tenants SET policy_release_id=$2,policy_generation=$3 WHERE id=$1",
            [tenant, release, next]
          )

          Store.query(
            tx,
            "INSERT INTO axiom_publications(tenant_id,generation,kind,from_release,to_release,actor,reason,request_id,fingerprint,result) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)",
            [
              tenant,
              next,
              kind,
              state.release,
              release,
              actor,
              reason,
              request_id,
              fingerprint,
              result
            ]
          )

          result
      end
    end)
  end

  def snapshot(conn, tenant, principal, opts \\ []) do
    Store.transaction(
      conn,
      fn tx ->
        Store.valid!(tx, [principal])
        state = Store.tenant!(tx, tenant)
        {kind, status} = Store.node!(tx, tenant, principal)
        Store.require!(tx, Domain.principal_kind(kind), :invalid_principal)
        scope = Keyword.get(opts, :resource_scope)

        scope_key = snapshot_scope!(tx, tenant, scope)
        release = Keyword.get(opts, :release_id, state.release)

        Store.require!(
          tx,
          is_nil(release) or (Domain.revision(release) and release > 0),
          :invalid_release
        )

        policy =
          case Store.query(
                 tx,
                 "SELECT body,digest FROM axiom_releases WHERE tenant_id=$1 AND id=$2",
                 [tenant, release]
               ) do
            [[body, digest]] -> %{"release_id" => release, "body" => body, "digest" => digest}
            [] when is_nil(release) -> nil
            [] -> Postgrex.rollback(tx, :release_not_found)
          end

        assignments =
          Store.query(
            tx,
            "SELECT role,scope,status FROM axiom_assignments WHERE tenant_id=$1 AND principal=$2 AND ($3::text IS NULL OR scope=$3) ORDER BY role,scope",
            [tenant, principal, scope_key]
          )
          |> Enum.map(fn [role, scope, st] ->
            %{"role" => role, "scope" => scope, "status" => st}
          end)

        relations =
          Store.query(
            tx,
            "SELECT relation,object,status FROM axiom_relations WHERE tenant_id=$1 AND subject=$2 AND ($3::text IS NULL OR object=$3) ORDER BY relation,object",
            [tenant, principal, scope_key]
          )
          |> Enum.map(fn [rel, obj, st] ->
            %{"relation" => rel, "object" => obj, "status" => st}
          end)

        data = %{
          "data_schema_version" => 1,
          "tenant_id" => tenant,
          "principal" => principal,
          "principal_status" => status,
          "policy" => policy,
          "policy_generation" => state.generation,
          "assignment_revision" => state.assignment_revision,
          "assignments" => assignments,
          "relations" => relations
        }

        data = bind_snapshot(data, scope, state.release)

        etag = Domain.etag(data)

        snapshot_response!(tx, data, etag, scope, principal, opts)
      end,
      :read
    )
  end

  defp snapshot_response!(tx, data, etag, scope, principal, opts) do
    selection = if Keyword.has_key?(opts, :release_id), do: "release", else: "current"
    bundle = if scope, do: Scope.bundle(data, selection, etag)
    response = %{"status" => "ok", "etag" => etag, "data" => data}
    response = if scope, do: Map.put(response, "revision_bundle", bundle), else: response

    cond do
      Keyword.has_key?(opts, :if_revision_bundle) ->
        previous = Keyword.fetch!(opts, :if_revision_bundle)

        conditional_response!(
          tx,
          previous,
          bundle,
          response,
          scope,
          principal,
          selection,
          opts[:release_id]
        )

      Keyword.get(opts, :if_none_match) == etag ->
        Map.drop(response, ["data"]) |> Map.put("status", "not_modified")

      true ->
        response
    end
  end

  defp conditional_response!(tx, previous, bundle, response, scope, principal, selection, release) do
    case Scope.validate_bundle(previous, scope, principal, selection, release) do
      :ok -> conditional_response(previous === bundle, bundle, response)
      {:error, reason} -> Postgrex.rollback(tx, reason)
    end
  end

  defp conditional_response(true, bundle, response),
    do:
      response
      |> Map.drop(["data"])
      |> Map.put("status", "not_modified")
      |> Map.put("revision_bundle", bundle)

  defp conditional_response(false, _bundle, response), do: Map.put(response, "status", "changed")

  defp snapshot_scope!(_tx, _tenant, nil), do: nil

  defp snapshot_scope!(tx, tenant, scope) do
    Store.require!(tx, Scope.valid?(scope) and scope["tenant_id"] == tenant, :invalid_scope)
    Store.resource_scope!(tx, scope)
  end

  defp bind_snapshot(data, nil, _head), do: data

  defp bind_snapshot(data, scope, head) do
    data |> Map.put("policy_head_release_id", head) |> Scope.bind(scope)
  end

  def history(conn, tenant) do
    Store.transaction(
      conn,
      fn tx ->
        Store.tenant!(tx, tenant)

        %{
          "assignments" =>
            Store.query(
              tx,
              "SELECT revision,kind,payload,actor FROM axiom_assignment_events WHERE tenant_id=$1 ORDER BY revision",
              [tenant]
            ),
          "publications" =>
            Store.query(
              tx,
              "SELECT generation,kind,from_release,to_release,actor,reason FROM axiom_publications WHERE tenant_id=$1 ORDER BY generation",
              [tenant]
            )
        }
      end,
      :read
    )
  end
end
