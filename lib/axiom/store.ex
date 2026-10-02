defmodule Axiom.Store do
  @moduledoc "PostgreSQL shell. All statements parameterized; every query is tenant-scoped."
  alias Axiom.{Domain, Scope}

  def query(conn, sql, params \\ []) do
    Postgrex.query!(conn, sql, params).rows
  end

  def transaction(conn, fun, mode \\ :write) do
    Postgrex.transaction(conn, fn tx ->
      if mode == :read, do: query(tx, "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
      fun.(tx)
    end)
  rescue
    error in Postgrex.Error ->
      # Driver SQL and detail can expose values; return only a stable category.
      case error.postgres[:code] do
        code
        when code in [
               :check_violation,
               :foreign_key_violation,
               :unique_violation,
               :not_null_violation
             ] ->
          {:error, :constraint}

        _ ->
          {:error, :database}
      end
  end

  def require!(tx, true, _reason), do: tx
  def require!(tx, false, reason), do: Postgrex.rollback(tx, reason)
  def valid!(tx, values), do: require!(tx, Domain.identifiers(values), :invalid_identifier)

  def tenant!(tx, tenant, lock \\ false) do
    valid!(tx, [tenant])
    suffix = if lock, do: " FOR UPDATE", else: ""

    case query(
           tx,
           "SELECT assignment_revision,policy_generation,policy_release_id FROM axiom_tenants WHERE id=$1" <>
             suffix,
           [tenant]
         ) do
      [[ar, generation, release]] ->
        %{assignment_revision: ar, generation: generation, release: release}

      [] ->
        Postgrex.rollback(tx, :tenant_not_found)
    end
  end

  def node!(tx, tenant, key) do
    case query(tx, "SELECT kind,status FROM axiom_nodes WHERE tenant_id=$1 AND key=$2", [
           tenant,
           key
         ]) do
      [[kind, status]] -> {kind, status}
      [] -> Postgrex.rollback(tx, :node_not_found)
    end
  end

  def resource_scope!(tx, scope) do
    require!(tx, Scope.valid?(scope), :invalid_scope)
    tenant!(tx, scope["tenant_id"])

    case query(
           tx,
           "SELECT node_key FROM axiom_resource_scopes WHERE tenant_id=$1 AND space_id=$2 AND scenario_id=$3 AND local_id=$4",
           [scope["tenant_id"], scope["space_id"], scope["scenario_id"], scope["local_id"]]
         ) do
      [[key]] ->
        require!(tx, key == Scope.node_key(scope), :scope_collision)
        key

      [] ->
        Postgrex.rollback(tx, :scope_not_found)
    end
  end

  def role_keys(tx, tenant),
    do:
      query(tx, "SELECT key FROM axiom_roles WHERE tenant_id=$1 ORDER BY key", [tenant])
      |> List.flatten()

  def next_revision!(tx, current) do
    case Domain.next_revision(current) do
      {:ok, next} -> next
      {:error, reason} -> Postgrex.rollback(tx, reason)
    end
  end

  def bump!(tx, tenant, kind, payload, actor, next) do
    [[revision]] =
      query(
        tx,
        "UPDATE axiom_tenants SET assignment_revision=$2 WHERE id=$1 RETURNING assignment_revision",
        [tenant, next]
      )

    query(
      tx,
      "INSERT INTO axiom_assignment_events(tenant_id,revision,kind,payload,actor) VALUES($1,$2,$3,$4,$5)",
      [tenant, revision, kind, payload, actor]
    )

    %{"assignment_revision" => revision}
  end
end
