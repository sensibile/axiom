{:ok,c}=Postgrex.start_link(Axiom.TestDatabase.options())
alias Axiom.Store
m=9223372036854775807
body=fn a -> %{"schema_version"=>1,"rules"=>[%{"effect"=>"allow","role"=>"reader","resource_kind"=>"document","actions"=>[a]}]} end
for seed<-[20261003,20261004,20261005] do
  :rand.seed(:exsss,{seed,317,817})
  t="final-random-"<>Base.encode16(:crypto.strong_rand_bytes(12),case: :lower)
  {:ok,_}=Axiom.create_tenant(c,t)
  {:ok,_}=Axiom.register_role(c,t,"reader",0,"audit")
  {:ok,_}=Axiom.register_node(c,t,"alice","person",1,"audit")
  {:ok,_}=Axiom.register_node(c,t,"doc","document",2,"audit")
  # Compressed prefix sets independent counters near terminal without creating historical fake events.
  Store.query(c,"UPDATE axiom_tenants SET assignment_revision=$2,policy_generation=$3 WHERE id=$1",[t,m-15,m-11])
  {:ok,_}=Axiom.save_draft(c,t,body.("read"),0)
  Store.query(c,"UPDATE axiom_drafts SET revision=$2 WHERE tenant_id=$1",[t,m-9])
  initial=%{ar: m-15,g: m-11,dr: m-9,status: "active",a: nil,head: nil,releases: %{},draft: body.("read"),receipts: [],events: 3,pubs: 0}
  final=Enum.reduce(1..200,initial,fn step,r ->
    op=:rand.uniform(7)
    next=case op do
      1 ->
        value=if r.status=="active",do: "suspended",else: "active"
        response=Axiom.set_principal_status(c,t,"alice",value,r.ar,"audit")
        if r.ar==m do
          {:error,:revision_exhausted}=response; r
        else
          {:ok,%{"assignment_revision"=>ar}}=response
          true=ar==r.ar+1
          %{r|ar: ar,status: value,events: r.events+1}
        end
      2 ->
        value=if r.a=="active",do: "revoked",else: "active"
        response=Axiom.put_assignment(c,t,"alice","reader","doc",value,r.ar,"audit")
        if r.ar==m do
          {:error,:revision_exhausted}=response; r
        else
          {:ok,%{"assignment_revision"=>ar}}=response
          true=ar==r.ar+1
          %{r|ar: ar,a: value,events: r.events+1}
        end
      3 ->
        b=body.("action-#{step}")
        response=Axiom.save_draft(c,t,b,r.dr)
        if r.dr==m do
          {:error,:revision_exhausted}=response; r
        else
          {:ok,%{"draft_revision"=>dr}}=response
          true=dr==r.dr+1
          %{r|dr: dr,draft: b}
        end
      4 ->
        args=[c,t,r.dr,r.g,"publish-#{step}","audit"]
        response=apply(Axiom,:publish,args)
        if r.g==m do
          {:error,:revision_exhausted}=response; r
        else
          {:ok,p}=response
          true=p["policy_generation"]==r.g+1
          id=p["policy_release_id"]
          %{r|g: r.g+1,head: id,releases: Map.put(r.releases,id,r.draft),pubs: r.pubs+1,receipts: [{:publish,args,response}|r.receipts]}
        end
      5 when map_size(r.releases)>0 ->
        id=r.releases|>Map.keys()|>Enum.sort()|>Enum.at(rem(step,map_size(r.releases)))
        args=[c,t,id,r.g,"rollback-#{step}","audit","reason"]
        response=apply(Axiom,:rollback_policy,args)
        if r.g==m do
          {:error,:revision_exhausted}=response; r
        else
          {:ok,p}=response
          true=p["policy_generation"]==r.g+1
          %{r|g: r.g+1,head: id,pubs: r.pubs+1,receipts: [{:rollback_policy,args,response}|r.receipts]}
        end
      6 when r.receipts != [] ->
        {fun,args,expected}=Enum.at(r.receipts,rem(step,length(r.receipts)))
        ^expected=apply(Axiom,fun,args)
        r
      7 ->
        {:error,:conflict}=Axiom.set_principal_status(c,t,"alice","active",r.ar-1,"audit")
        r
      _ -> r
    end
    {:ok,s}=Axiom.snapshot(c,t,"alice")
    d=s["data"]
    true=d["assignment_revision"]==next.ar
    true=d["policy_generation"]==next.g
    true=d["principal_status"]==next.status
    true=Enum.map(d["assignments"],& &1["status"])==if(next.a,do: [next.a],else: [])
    true=(if d["policy"],do: d["policy"]["body"],else: nil)==Map.get(next.releases,next.head)
    {:ok,draft}=Axiom.draft(c,t)
    true=draft==%{"draft_revision"=>next.dr,"body"=>next.draft}
    [[events]]=Store.query(c,"SELECT count(*) FROM axiom_assignment_events WHERE tenant_id=$1",[t])
    [[pubs]]=Store.query(c,"SELECT count(*) FROM axiom_publications WHERE tenant_id=$1",[t])
    [[releases]]=Store.query(c,"SELECT count(*) FROM axiom_releases WHERE tenant_id=$1",[t])
    true=events==next.events
    true=pubs==next.pubs
    true=releases==map_size(next.releases)
    IO.puts("seed=#{seed} step=#{step} op=#{op} ar=#{next.ar} dr=#{next.dr} g=#{next.g} events=#{events} pubs=#{pubs}")
    next
  end)
  true=final.ar==m and final.dr==m and final.g==m
  IO.inspect(%{seed: seed,fixture: t,final: final},label: "RANDOM PASS")
end
