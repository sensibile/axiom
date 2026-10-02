defmodule Axiom.Scope do
  @moduledoc "Pure exact logical resource identity, independent of physical placement and data cuts."
  alias Axiom.Domain
  @fields ~w(local_id scenario_id space_id tenant_id)

  def valid?(scope) when is_map(scope) do
    Enum.sort(Map.keys(scope)) == @fields and Domain.identifiers(Map.values(scope))
  end

  def valid?(_scope), do: false

  # Internal node adapter only. The complete tuple is stored and compared on every lookup;
  # a digest collision must fail rather than alias two logical resources.
  def node_key(scope), do: "r" <> binary_part(Domain.digest(scope), 0, 63)

  @bundle_fields ~w(assignment_revision bundle_schema_version data_schema_version etag policy_generation policy_head_release_id policy_release_id policy_selection principal principal_status resource_scope tenant_id)

  def bundle(data, selection, etag) do
    %{
      "bundle_schema_version" => 1,
      "data_schema_version" => data["data_schema_version"],
      "tenant_id" => data["tenant_id"],
      "resource_scope" => data["resource_scope"],
      "principal" => data["principal"],
      "principal_status" => data["principal_status"],
      "policy_selection" => selection,
      "policy_release_id" => if(data["policy"], do: data["policy"]["release_id"]),
      "policy_head_release_id" => data["policy_head_release_id"],
      "policy_generation" => data["policy_generation"],
      "assignment_revision" => data["assignment_revision"],
      "etag" => etag
    }
  end

  def validate_bundle(bundle, scope, principal, selection, release) when is_map(bundle) do
    valid = valid_bundle?(bundle)

    cond do
      not valid or not valid?(scope) ->
        {:error, :invalid_revision_bundle}

      not binding_matches?(bundle, scope, principal, selection, release) ->
        {:error, :revision_bundle_binding_mismatch}

      true ->
        :ok
    end
  end

  def validate_bundle(_bundle, _scope, _principal, _selection, _release),
    do: {:error, :invalid_revision_bundle}

  defp valid_bundle?(bundle) do
    Enum.all?([
      Enum.sort(Map.keys(bundle)) == @bundle_fields,
      bundle["bundle_schema_version"] === 1,
      bundle["data_schema_version"] === 2,
      valid?(bundle["resource_scope"]),
      Domain.identifiers([bundle["tenant_id"], bundle["principal"]]),
      Domain.status(bundle["principal_status"]),
      bundle["policy_selection"] in ["current", "release"],
      Domain.revision(bundle["policy_generation"]),
      Domain.revision(bundle["assignment_revision"]),
      nullable_release?(bundle["policy_release_id"]),
      nullable_release?(bundle["policy_head_release_id"]),
      valid_etag?(bundle["etag"])
    ])
  end

  defp binding_matches?(bundle, scope, principal, selection, release) do
    Enum.all?([
      bundle["resource_scope"] == scope,
      bundle["tenant_id"] == scope["tenant_id"],
      bundle["principal"] == principal,
      bundle["policy_selection"] == selection,
      selection != "release" or bundle["policy_release_id"] == release
    ])
  end

  defp valid_etag?(etag) when is_binary(etag), do: String.match?(etag, ~r/\A"[0-9a-f]{64}"\z/)
  defp valid_etag?(_etag), do: false

  defp nullable_release?(nil), do: true
  defp nullable_release?(id), do: Domain.revision(id) and id > 0

  def bind(data, scope) do
    Map.merge(data, %{
      "data_schema_version" => 2,
      "resource_scope" => scope,
      "assignments" => Enum.map(data["assignments"], &Map.put(&1, "scope", scope)),
      "relations" => Enum.map(data["relations"], &Map.put(&1, "object", scope)),
      "consumer_contract" => %{
        "decision" => "not_evaluated",
        "binding" => ~w(tenant_id principal resource_scope policy.release_id),
        "freshness" =>
          ~w(policy_head_release_id policy_generation assignment_revision principal_status),
        "knowledge_cut" => "external_not_verified",
        "cache_reuse" => "requires_current_authority_revalidation"
      }
    })
  end
end
