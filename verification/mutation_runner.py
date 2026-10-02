from pathlib import Path
import shutil, subprocess,json,hashlib
root=Path(__file__).resolve().parent.parent
out=root/'verification/evidence'
work=root/'verification/mutation-copy'
mutations=[
 ('read_committed','lib/axiom/store.ex','SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY','SET TRANSACTION ISOLATION LEVEL READ COMMITTED READ ONLY'),
 ('assignment_cas','lib/axiom.ex','Store.require!(tx, state.assignment_revision == revision, :conflict)','Store.require!(tx, true, :conflict)'),
 ('retry_fingerprint','lib/axiom.ex','[[^fingerprint, result]] ->','[[_, result]] ->'),
 ('rollback_revives','lib/axiom.ex','{release_id, reason}','Store.query(tx, "UPDATE axiom_assignments SET status=\'active\' WHERE tenant_id=$1", [tenant])\n        Store.query(tx, "UPDATE axiom_nodes SET status=\'active\' WHERE tenant_id=$1", [tenant])\n        {release_id, reason}')
]
summary=[]
for name,file,old,new in mutations:
 if work.exists(): shutil.rmtree(work)
 work.mkdir()
 for item in ['lib','priv','test','vendor','_build']:
  shutil.copytree(root/item,work/item)
 for item in ['mix.exs','.formatter.exs']:
  shutil.copy2(root/item,work/item)
 p=work/file
 s=p.read_text(); assert s.count(old)==1,(name,s.count(old)); p.write_text(s.replace(old,new))
 result=subprocess.run(['mix','test','--seed','20261002'],cwd=work,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
 (out/f'mutation-{name}.log').write_text(result.stdout)
 summary.append({'mutation':name,'file':file,'before':old,'after':new,'exit':result.returncode,'test_result':[line for line in result.stdout.splitlines() if 'Result:' in line or 'failure' in line]})
 print(name,result.returncode,summary[-1]['test_result'],flush=True)
(out/'mutation-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
shutil.rmtree(work)
