run_id = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
Application.put_env(:axiom, :independent_run, run_id)
IO.inspect(run_id, label: "fixture_run_namespace")
ExUnit.start(seed: 20_261_002)
root = Path.expand("../..", __DIR__)
opts = Axiom.TestDatabase.options()
{:ok, identity} = Postgrex.start_link(Keyword.put(opts, :parameters, []))
Process.unlink(identity)
q = fn sql -> Postgrex.query!(identity, sql, []).rows end

[["axiom_test", "axiom_test", 5432, version, address]] =
  q.(
    "SELECT current_database(),current_user,inet_server_port(),current_setting('server_version_num')::integer,inet_server_addr()::text"
  )

true = version >= 170_000 and version < 180_000

IO.inspect(
  %{
    database: "axiom_test",
    user: "axiom_test",
    server_port: 5432,
    version: version,
    address: address
  },
  label: "verified_identity"
)

public = fn ->
  for [table] <-
        q.("SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename") do
    [
      table,
      q.("SELECT row_to_json(t)::text FROM public.\"#{table}\" t ORDER BY row_to_json(t)::text")
    ]
  end
end

before = public.()
File.write!(Path.join(__DIR__, "public-before.json"), Jason.encode!(before))
schema = "axiom_fresh_bundle_version_20261002"
q.("CREATE SCHEMA IF NOT EXISTS #{schema}")

{_, 0} =
  System.cmd(
    "psql",
    [
      "-X",
      "--no-password",
      "--set",
      "ON_ERROR_STOP=1",
      "--host",
      opts[:hostname],
      "--port",
      to_string(opts[:port]),
      "--username",
      opts[:username],
      "--dbname",
      opts[:database],
      "--file",
      Path.join(root, "priv/schema.sql")
    ],
    env: [{"PGPASSWORD", opts[:password]}, {"PGOPTIONS", "-c search_path=#{schema}"}],
    stderr_to_stdout: true
  )

{:ok, conn} = Postgrex.start_link(Keyword.put(opts, :parameters, search_path: schema))
Process.unlink(conn)
Application.put_env(:axiom, :independent_conn, conn)

Application.put_env(
  :axiom,
  :independent_opts,
  Keyword.put(opts, :parameters, search_path: schema)
)

ExUnit.after_suite(fn _ ->
  after_rows = public.()
  File.write!(Path.join(__DIR__, "public-after.json"), Jason.encode!(after_rows))
  IO.inspect(before == after_rows, label: "public_preserved")
end)

defmodule IndependentBundleProbe do
  use ExUnit.Case, async: false
  defp ok({:ok, x}), do: x
  defp q(c, sql, args \\ []), do: Postgrex.query!(c, sql, args).rows
  defp rev(c,t), do: q(c,"SELECT assignment_revision FROM axiom_tenants WHERE id=$1",[t]) |> hd() |> hd()
  defp scope(t), do: %{"tenant_id"=>t,"space_id"=>"space","scenario_id"=>"base","local_id"=>"same"}
  defp fixture do
    c=Application.fetch_env!(:axiom,:independent_conn)
    t="b"<>Application.fetch_env!(:axiom,:independent_run)<>Integer.to_string(System.unique_integer([:positive]))
    ok(Axiom.create_tenant(c,t))
    ok(Axiom.register_role(c,t,"reader",0,"actor"))
    ok(Axiom.register_node(c,t,"alice","person",1,"actor"))
    ok(Axiom.register_node(c,t,"bob","person",2,"actor"))
    s=scope(t)
    ok(Axiom.register_resource_scope(c,s,"document",3,"actor"))
    body=%{"schema_version"=>1,"rules"=>[%{"role"=>"reader","resource_kind"=>"document","actions"=>["read"],"effect"=>"allow"}]}
    ok(Axiom.save_draft(c,t,body,0))
    pub=ok(Axiom.publish(c,t,1,0,"pub","actor"))
    {c,t,s,body,pub["policy_release_id"]}
  end
  defp read(c,s,opts \\ []), do: ok(Axiom.resource_snapshot(c,s,"alice",opts))
  defp changed(c,s,previous,opts \\ []) do
    current=read(c,s,opts)
    result=read(c,s,Keyword.put(opts,:if_revision_bundle,previous))
    assert result["status"]=="changed"
    assert result["data"]==current["data"]
    assert result["revision_bundle"]==current["revision_bundle"]
    result["revision_bundle"]
  end
  test "independent event trace: assignment/relation ABA, no-op, suspension, historical publish and rollback" do
    {c,t,s,body,r}=fixture()
    original=read(c,s)
    b=original["revision_bundle"]
    assert read(c,s,if_revision_bundle: b)["status"]=="not_modified"
    actions=[{:assignment,"active"},{:assignment,"revoked"},{:assignment,"active"},{:assignment,"active"},{:relation,"active"},{:relation,"revoked"},{:relation,"active"},{:status,"suspended"},{:status,"active"},{:status,"active"}]
    {last,n}=Enum.reduce(actions,{b,4},fn {kind,status},{previous,n}->
      case kind do
        :assignment->ok(Axiom.put_resource_assignment(c,s,"alice","reader",status,n,"actor"))
        :relation->ok(Axiom.put_resource_relation(c,s,"alice","owner",status,n,"actor"))
        :status->ok(Axiom.set_principal_status(c,t,"alice",status,n,"actor"))
      end
      next=changed(c,s,previous)
      assert next["assignment_revision"]==n+1
      assert next["policy_generation"]==1
      IO.inspect({kind,status,n+1},label: "event_oracle")
      {next,n+1}
    end)
    assert last["assignment_revision"]==n
    pinned=read(c,s,release_id: r)["revision_bundle"]
    ok(Axiom.save_draft(c,t,body,1))
    ok(Axiom.publish(c,t,2,1,"samecontent","actor"))
    pinned2=changed(c,s,pinned,release_id: r)
    assert pinned2["policy_generation"]==2
    assert pinned2["policy_release_id"]==r
    assert pinned2["policy_head_release_id"]!=r
    assert pinned2["assignment_revision"]==n
    ok(Axiom.rollback_policy(c,t,r,2,"rollback","actor","reason"))
    pinned3=changed(c,s,pinned2,release_id: r)
    assert pinned3["policy_generation"]==3
    assert pinned3["policy_head_release_id"]==r
    ok(Axiom.put_resource_assignment(c,s,"alice","reader","revoked",n,"actor"))
    ok(Axiom.set_principal_status(c,t,"alice","suspended",n+1,"actor"))
    historical=read(c,s,release_id: r,if_revision_bundle: pinned3)
    assert historical["status"]=="changed"
    assert historical["data"]["principal_status"]=="suspended"
    assert hd(historical["data"]["assignments"])["status"]=="revoked"
  end
  test "strict maps, binding tampering, isolation and conservative invalidation" do
    {c,t,s,_,r}=fixture()
    b=read(c,s)["revision_bundle"]
    for key<-Map.keys(b) do
      assert Axiom.resource_snapshot(c,s,"alice",if_revision_bundle: Map.delete(b,key))=={:error,:invalid_revision_bundle}
      assert Axiom.resource_snapshot(c,s,"alice",if_revision_bundle: Map.put(b,key,[]))=={:error,:invalid_revision_bundle}
    end
    for bad<-[nil,%{},Map.put(b,"extra",0),Map.put(b,"bundle_schema_version",2),Map.put(b,"assignment_revision",-1),Map.put(b,"etag","x")] do
      assert Axiom.resource_snapshot(c,s,"alice",if_revision_bundle: bad)=={:error,:invalid_revision_bundle}
    end
    for forged<-[Map.put(b,"principal","bob"),Map.put(b,"tenant_id","other"),Map.put(b,"resource_scope",Map.put(s,"space_id","other")),Map.put(b,"policy_selection","release")] do
      assert Axiom.resource_snapshot(c,s,"alice",if_revision_bundle: forged)=={:error,:revision_bundle_binding_mismatch}
    end
    assert Axiom.resource_snapshot(c,s,"alice",release_id: r,if_revision_bundle: b)=={:error,:revision_bundle_binding_mismatch}
    assert Axiom.resource_snapshot(c,s,"alice",if_revision_bundle: b,if_none_match: b["etag"])=={:error,:invalid_options}
    forged=Map.put(b,"assignment_revision",99)
    assert read(c,s,if_revision_bundle: forged)["status"]=="changed"
    ok(Axiom.put_resource_assignment(c,s,"bob","reader","active",4,"actor"))
    next=changed(c,s,b)
    assert next["assignment_revision"]==5
    assert read(c,s)["data"]["assignments"]==[]
    for field<-["space_id","scenario_id"] do
      other=Map.put(s,field,"other")
      ok(Axiom.register_resource_scope(c,other,"document",rev(c,t),"actor"))
      assert Axiom.resource_snapshot(c,other,"alice",if_revision_bundle: next)=={:error,:revision_bundle_binding_mismatch}
    end
    {_,_,foreign,_,_}=fixture()
    assert Axiom.resource_snapshot(c,foreign,"alice",if_revision_bundle: next)=={:error,:revision_bundle_binding_mismatch}
    stable=read(c,s)["revision_bundle"]
    ok(Axiom.set_principal_status(c,foreign["tenant_id"],"alice","suspended",4,"actor"))
    assert read(c,s,if_revision_bundle: stable)["status"]=="not_modified"
  end
  test "float schema versions are rejected: minimal contract reproducer" do
    {c,_,s,_,_}=fixture()
    b=read(c,s)["revision_bundle"]
    results=for {field,value}<- [{"bundle_schema_version",1.0},{"data_schema_version",2.0}] do
      got=Axiom.resource_snapshot(c,s,"alice",if_revision_bundle: Map.put(b,field,value))
      IO.inspect({field,value,got},label: "float_reproducer")
      {field,got}
    end
    assert Enum.all?(results, fn {_,got}->got=={:error,:invalid_revision_bundle} end)
  end
  test "real API barrier: revoke and publish commit after first SELECT share old bundle/data snapshot" do
    {c,t,s,body,r}=fixture()
    ok(Axiom.put_resource_assignment(c,s,"alice","reader","active",4,"actor"))
    old=read(c,s)
    opts=Application.fetch_env!(:axiom,:independent_opts)
    {:ok,locker}=Postgrex.start_link(opts)
    {:ok,reader}=Postgrex.start_link(opts)
    Process.unlink(locker)
    Process.unlink(reader)
    parent=self()
    lock=Task.async(fn->Postgrex.transaction(locker,fn tx->
      q(tx,"LOCK TABLE axiom_resource_scopes IN ACCESS EXCLUSIVE MODE")
      send(parent,:locked)
      receive do :unlock->:ok after 10000->raise "unlock timeout" end
    end) end)
    assert_receive :locked,5000
    task=Task.async(fn->Axiom.resource_snapshot(reader,s,"alice",if_revision_bundle: old["revision_bundle"]) end)
    wait=fn wait,n->
      rows=q(c,"SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock' AND query LIKE 'SELECT node_key FROM axiom_resource_scopes%'",[])
      if rows==[[0]] do
        if n==0,do: raise("reader never blocked")
        Process.sleep(10)
        wait.(wait,n-1)
      end
    end
    wait.(wait,500)
    # Writer SQL uses only this fixture. It deliberately bypasses node lock while atomically changing
    # policy head plus facts; expected values are supplied independently, not derived from read data.
    ok(Axiom.save_draft(c,t,body,1))
    Postgrex.transaction(c,fn tx->
      ok(Axiom.publish(tx,t,2,1,"barrierpub","actor"))
      ok(Axiom.put_assignment(tx,t,"alice","reader",Axiom.Scope.node_key(s),"revoked",5,"actor"))
      ok(Axiom.set_principal_status(tx,t,"alice","suspended",6,"actor"))
    end) |> ok()
    send(lock.pid,:unlock)
    assert {:ok,:ok}=Task.await(lock)
    assert {:ok,result}=Task.await(task)
    assert result["status"]=="not_modified"
    assert result["revision_bundle"]==old["revision_bundle"]
    assert read(c,s,if_revision_bundle: old["revision_bundle"])["status"]=="changed"
    IO.inspect({r,body["schema_version"]},label: "barrier_fixture")
    GenServer.stop(locker)
    GenServer.stop(reader)
  end
  test "fresh independent version matrix and ETag contract" do
    {c,t,s,body,_}=fixture()
    original=read(c,s)
    b=original["revision_bundle"]
    for {field,valid} <- [{"bundle_schema_version",1},{"data_schema_version",2},{"assignment_revision",4},{"policy_generation",1},{"policy_release_id",b["policy_release_id"]},{"policy_head_release_id",b["policy_head_release_id"]}], bad <- [valid/1,valid+0.5,true,false,to_string(valid),[],%{}] do
      got=Axiom.resource_snapshot(c,s,"alice",if_revision_bundle: Map.put(b,field,bad))
      assert got=={:error,:invalid_revision_bundle}, inspect({field,bad,got})
    end
    for field <- ["bundle_schema_version","data_schema_version","assignment_revision","policy_generation"] do
      assert Axiom.resource_snapshot(c,s,"alice",if_revision_bundle: Map.put(b,field,nil))=={:error,:invalid_revision_bundle}
    end
    for field <- ["policy_release_id","policy_head_release_id"] do
      assert read(c,s,if_revision_bundle: Map.put(b,field,nil))["status"]=="changed"
    end
    assert read(c,s,if_revision_bundle: b)["status"]=="not_modified"
    legacy=read(c,s,if_none_match: original["etag"])
    assert legacy["status"]=="not_modified"
    refute Map.has_key?(legacy,"data")
    assert legacy["etag"]===original["etag"]
    assert read(c,s,if_none_match: "stale")["status"]=="ok"
    ok(Axiom.put_resource_assignment(c,s,"alice","reader","active",4,"actor"))
    granted=read(c,s)
    ok(Axiom.put_resource_assignment(c,s,"alice","reader","revoked",5,"actor"))
    assert read(c,s,if_revision_bundle: granted["revision_bundle"])["status"]=="changed"
    assert read(c,s,if_none_match: granted["etag"])["status"]=="ok"
    stable=read(c,s)
    ok(Axiom.save_draft(c,t,body,1))
    ok(Axiom.publish(c,t,2,1,"matrixpub","actor"))
    assert read(c,s,if_revision_bundle: stable["revision_bundle"])["status"]=="changed"
    assert read(c,s,if_none_match: stable["etag"])["status"]=="ok"
    assert Axiom.Domain.policy(body,["reader"])=={:ok,body}
    for bad <- [1.0,1.5,true,false,nil,"1",[],%{},0,2] do
      assert Axiom.Domain.policy(Map.put(body,"schema_version",bad),["reader"])=={:error,:unsupported_schema}
    end
    assert Axiom.Domain.policy(Map.delete(body,"schema_version"),["reader"])=={:error,:invalid_policy}
    assert Axiom.Domain.policy(Map.put(body,"extra",1),["reader"])=={:error,:invalid_policy}
  end

end
