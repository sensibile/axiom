import os, pathlib, tempfile, subprocess, shutil, json, hashlib
base=pathlib.Path('/Users/tonton/Documents/workspace/alaya')
out=pathlib.Path('/tmp/alaya-independent-gates-20261002')
results={}
def run(args,cwd,env=None):
 p=subprocess.run(args,cwd=cwd,env=env,capture_output=True,text=True)
 return {'exit':p.returncode,'output':p.stdout+p.stderr}
for name in ('akashic','axiom'):
 src=base/name
 root=pathlib.Path(tempfile.mkdtemp(prefix=name+'-gate-fixture-')).resolve()
 (root/'.githooks').mkdir();(root/'scripts').mkdir();(root/'nested').mkdir()
 shutil.copy2(src/'.githooks/pre-commit',root/'.githooks/pre-commit')
 shutil.copy2(src/'.gitignore',root/'.gitignore')
 run(['git','init','-q'],root);run(['git','config','--local','core.hooksPath','.githooks'],root)
 d={'fixture':str(root),'hooks':{},'ignore':{}}
 for code in (0,7):
  (root/'scripts/check').write_text('#!/bin/sh\ntest "$(pwd -P)" = "'+str(root)+'" || exit 99\ntest "$1" = precommit || exit 98\nexit '+str(code)+'\n')
  (root/'scripts/check').chmod(0o755)
  d['hooks'][str(code)]=run(['git','hook','run','pre-commit'],root/'nested')
 # Staged bad Elixir input, working-tree valid; formatter only sees valid tree.
 (root/'.formatter.exs').write_text('[inputs: ["lib/**/*.ex"]]\n');(root/'lib').mkdir()
 (root/'lib/probe.ex').write_text('defmodule Probe do\ndef value, do: (\nend\n')
 run(['git','add','lib/probe.ex'],root)
 (root/'lib/probe.ex').write_text('defmodule Probe do\n  def value, do: 1\nend\n')
 d['working_tree_format']=run(['mix','format','--check-formatted'],root)
 (root/'lib/probe.ex').write_text(subprocess.check_output(['git','show',':lib/probe.ex'],cwd=root,text=True))
 d['staged_materialized_format']=run(['mix','format','--check-formatted'],root)
 paths=['.env','.env.production','.env.example','nested/.env','secret.pem','secret.key','local.db','local.db-wal','local.sqlite3','local.sqlite3-wal','local.sqlite3-shm','data/rocksdb/CURRENT','data/rocksdb/000001.sst','.aws/credentials','.npmrc','.cache/foo','target/x','_build/x','elixir/_build/x','elixir/deps/x','deps/x','nested/erl_crash.dump','elixir/erl_crash.dump','__pycache__/x.pyc']
 for path in paths:
  d['ignore'][path]=run(['git','check-ignore','--no-index','-q',path],root)['exit']==0
 results[name]=d
 snapshot={}
 for p in src.rglob('*'):
  rel=p.relative_to(src)
  if any(x in {'.git','target','.cache','_build','deps','artifacts','verification','docs'} for x in rel.parts):continue
  if p.is_file():snapshot[str(rel)]=hashlib.sha256(p.read_bytes()).hexdigest()
 (out/(name+'-source-hashes.json')).write_text(json.dumps(snapshot,indent=2)+'\n')
(out/'fixture-results.json').write_text(json.dumps(results,indent=2)+'\n')
for name,d in results.items():
 print(name, 'hook exits', {k:v['exit'] for k,v in d['hooks'].items()},'format tree/staged',d['working_tree_format']['exit'],d['staged_materialized_format']['exit'])
 print('UNIGNORED', [p for p,v in d['ignore'].items() if not v])
