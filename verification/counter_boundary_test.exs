defmodule CounterBoundaryVerification do
  use ExUnit.Case, async: false
  alias Axiom.{Store,Domain}
  @last_input 9_223_372_036_854_775_806
  defp fresh(c) do
    t="verify-boundary-"<>Base.encode16(:crypto.strong_rand_bytes(8),case: :lower)
    {:ok,_}=Axiom.create_tenant(c,t)
    {:ok,_}=Axiom.register_role(c,t,"reader",0,"audit")
    t
  end
  defp body,do: %{"schema_version"=>1,"rules"=>[%{"effect"=>"allow","role"=>"reader","resource_kind"=>"document","actions"=>["read"]}]}
  setup do
    c=Application.fetch_env!(:axiom,:test_conn)
    {:ok,c: c,t: fresh(c)}
  end
  test "assignment success must not return an unusable next CAS revision",%{c: c,t: t} do
    Store.query(c,"UPDATE axiom_tenants SET assignment_revision=$2 WHERE id=$1",[t,@last_input])
    assert {:ok,result}=Axiom.register_role(c,t,"edge",@last_input,"audit")
    next=result["assignment_revision"]
    IO.puts("BOUNDARY assignment next=#{next} retry=#{inspect(Axiom.register_role(c,t,"later",next,"audit"))}")
    assert Domain.revision(next),"successful assignment counter is outside the accepted CAS domain"
  end
  test "saved draft must have a publishable revision",%{c: c,t: t} do
    {:ok,_}=Axiom.save_draft(c,t,body(),0)
    Store.query(c,"UPDATE axiom_drafts SET revision=$2 WHERE tenant_id=$1",[t,@last_input])
    assert {:ok,result}=Axiom.save_draft(c,t,body(),@last_input)
    next=result["draft_revision"]
    IO.puts("BOUNDARY draft next=#{next} publish=#{inspect(Axiom.publish(c,t,next,0,"edge","audit"))}")
    assert Domain.revision(next),"successful draft counter cannot be published or edited"
  end
  test "publication success must have a usable next generation",%{c: c,t: t} do
    {:ok,_}=Axiom.save_draft(c,t,body(),0)
    Store.query(c,"UPDATE axiom_tenants SET policy_generation=$2 WHERE id=$1",[t,@last_input])
    assert {:ok,result}=Axiom.publish(c,t,1,@last_input,"edge","audit")
    next=result["policy_generation"]
    IO.puts("BOUNDARY generation next=#{next} retry=#{inspect(Axiom.publish(c,t,1,next,"later","audit"))}")
    assert Domain.revision(next),"successful publication counter is outside the accepted CAS domain"
  end
end
