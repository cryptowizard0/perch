"""Sample sessions for the README screenshots, sent to an isolated perchd: never your real data.
usage: PERCH_HOME=/tmp/x perchd --no-http & python3 seed.py /tmp/x/perchd.sock"""
import socket, json, datetime, sys
SOCK = sys.argv[1]
now=datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)
def t(minutes): return (now-datetime.timedelta(minutes=minutes)).strftime('%Y-%m-%dT%H:%M:%SZ')
def send(req):
    s=socket.socket(socket.AF_UNIX); s.connect(SOCK)
    s.sendall((json.dumps(req)+'\n').encode()); r=s.makefile().readline(); s.close()
    assert json.loads(r)['ok'], r
G='perch-terminal://ghostty?cwd=/w/x&bundle=com.mitchellh.ghostty'
def rep(id,kind,mins,src='claude-code',**kw):
    send({"op":"session_report","report":dict(id=id,kind=kind,at=t(mins),source=src,title=id,link=G,**kw)})
rep('api-server','prompt',6,prompt='Fix the flaky retry test')
rep('api-server','waiting',1,detail='npm test')
send({"op":"add","item":{"title":"npm test","kind":"request","status":"waiting","source":"claude-code","options":["allow","deny"],"meta":{"session_id":"api-server","tool":"Bash"}}})
rep('web','prompt',9,src='codex',prompt='Clean up the build output')
rep('web','waiting',3,src='codex',detail='rm -rf dist/\nAnswer in the terminal: `rm -rf` is not on the allowlist')
rep('docs','prompt',14,prompt='Translate the setup guide')
rep('docs','failure',7,error='rate_limit')
rep('ios-app','prompt',2,src='codex',prompt='Migrate the settings screen to SwiftUI')
rep('infra','prompt',20,prompt='Bump the Terraform providers')
rep('infra','stop',5,last_message='All 42 tests pass; opened PR #128.')
rep('blog','prompt',50,prompt='Proofread the launch post')
rep('blog','stop',38,last_message='Fixed 6 typos and tightened the intro.')
send({"op":"session_seen","id":"blog"})
