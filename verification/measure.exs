{:ok,c}=Postgrex.start_link(Axiom.TestDatabase.options())
alias Axiom.Store
stats=fn xs ->
  s=Enum.sort(xs)
  %{n: length(s),min_us: hd(s),median_us: Enum.at(s,div(length(s),2)),p95_us: Enum.at(s,ceil(length(s)*0.95)-1),max_us: List.last(s)}
end
results=for size<-[1,200] do
  t="verify-cost-"<>Base.encode16(:crypto.strong_rand_bytes(8),case: :lower)
  {:ok,_}=Axiom.create_tenant(c,t)
  {:ok,_}=Axiom.register_role(c,t,"reader",0,"audit")
  {:ok,_}=Axiom.register_node(c,t,"alice","person",1,"audit")
  ar=Enum.reduce(1..size,2,fn n,r ->
    {:ok,_}=Axiom.register_node(c,t,"doc-#{n}","document",r,"audit")
    {:ok,_}=Axiom.put_assignment(c,t,"alice","reader","doc-#{n}","active",r+1,"audit")
    r+2
  end)
  rule=%{"effect"=>"allow","role"=>"reader","resource_kind"=>"document","actions"=>["read"]}
  body=%{"schema_version"=>1,"rules"=>List.duplicate(rule,if(size==1,do: 1,else: 100))}
  {:ok,_}=Axiom.save_draft(c,t,body,0)
  {:ok,p}=Axiom.publish(c,t,1,0,"initial","audit")
  for _<-1..10,do: Axiom.snapshot(c,t,"alice")
  read=for _<-1..100 do
    {us,{:ok,_}}=:timer.tc(fn->Axiom.snapshot(c,t,"alice")end);us
  end
  publish=for n<-1..30 do
    {:ok,_}=Axiom.save_draft(c,t,body,n)
    {us,{:ok,_}}=:timer.tc(fn->Axiom.publish(c,t,n+1,n,"p-#{n}","audit")end);us
  end
  writes=for n<-0..29 do
    {us,{:ok,_}}=:timer.tc(fn->Axiom.set_principal_status(c,t,"alice",if(rem(n,2)==0,do: "suspended",else: "active"),ar+n,"audit")end);us
  end
  {:ok,s}=Axiom.snapshot(c,t,"alice")
  [[jsonb_bytes]]=Store.query(c,"SELECT pg_column_size(body) FROM axiom_releases WHERE tenant_id=$1 AND id=$2",[t,p["policy_release_id"]])
  %{tenant: t,assignments: size,rules: length(body["rules"]),response_json_bytes: byte_size(Jason.encode!(s)),policy_jsonb_bytes: jsonb_bytes,snapshot: stats.(read),publish: stats.(publish),fact_change: stats.(writes)}
end
IO.puts(Jason.encode!(%{method: "local serial warm calls; real PG network+transaction included; draft excluded from publish; no throughput/SLA claim",datasets: results},pretty: true))
