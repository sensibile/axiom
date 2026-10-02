import pathlib,tempfile,shutil,subprocess,os,json
base=pathlib.Path('/Users/tonton/Documents/workspace/alaya');out=pathlib.Path('/tmp/alaya-independent-gates-20261002');results={}
for name in ('akashic','axiom'):
 root=pathlib.Path(tempfile.mkdtemp(prefix=name+'-stage-fixture-'));(root/'scripts').mkdir();(root/'bin').mkdir()
 shutil.copy2(base/name/'scripts/check',root/'scripts/check')
 if name=='akashic':
  for file in ('Cargo.toml','Cargo.lock','elixir/mix.exs','elixir/.formatter.exs','crates/akashic-engine/tests/boundary.rs','crates/akashic-engine/tests/integration.rs','.tool-versions'):
   p=root/file;p.parent.mkdir(parents=True,exist_ok=True);p.write_text('')
  (root/'crates/akashic-engine/Cargo.toml').write_text('[features]\nio = []\n')
  (root/'elixir/lib').mkdir();(root/'elixir/test').mkdir()
 for tool in ('cargo','rustc','elixir','mix','xcrun'):
  p=root/'bin'/tool
  p.write_text('''#!/usr/bin/env python3
import sys,os
name=os.path.basename(sys.argv[0]);args=sys.argv[1:]
if '--version' in args:
 print({'rustc':'rustc 1.98.1 fixture','cargo':'cargo fixture','elixir':'Elixir 1.20.4 fixture','mix':'Mix fixture'}[name]);sys.exit(0)
if name=='xcrun': print('/nonexistent');sys.exit(0)
if name=='elixir' and any('OTP_VERSION' in a for a in args): print('29.1.1');sys.exit(0)
with open(os.environ['TRACE'],'a') as f:f.write(name+' '+' '.join(args)+'\\n')
if os.environ.get('FAIL_KIND')=='compile' and name=='mix' and args and args[0]=='compile':sys.exit(7)
if os.environ.get('FAIL_KIND')=='format' and ((name=='mix' and args and args[0]=='format') or (name=='cargo' and args and args[0]=='fmt')):sys.exit(7)
if name=='cargo' and args and args[0]=='test':print('test result: ok. 1 passed')
if name=='elixir' or (name=='mix' and args and args[0]=='test'):print('Result: 1 passed')
''');p.chmod(0o755)
 env=os.environ.copy();env['PATH']=str(root/'bin')+':'+env['PATH'];env['TRACE']=str(root/'trace')
 cases={}
 for mode,fail in [('format',''),('precommit',''),('precommit','format'),('precommit','compile'),('review','')]:
  env['FAIL_KIND']=fail;(root/'trace').write_text('')
  p=subprocess.run([str(root/'scripts/check'),mode],cwd='/tmp',env=env,capture_output=True,text=True)
  cases[mode+'-'+(fail or 'success')]={'exit':p.returncode,'trace':(root/'trace').read_text().splitlines()}
 results[name]={'fixture':str(root),'cases':cases}
(out/'stage-results.json').write_text(json.dumps(results,indent=2)+'\n')
for name,d in results.items(): print(name,{k:v['exit'] for k,v in d['cases'].items()})
