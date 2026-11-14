"""Real two-process restart proof, using ONLY a newly owned OS-temporary store.

Run separately from pytest: its children install their own guards before importing
the backend. Never uses the user's manual persistent store or operational data.
"""
import argparse
from contextlib import contextmanager
from datetime import date, timedelta
import http.cookiejar
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

from testing_safety import _ACTIVE_ROOT, IsolatedEnvironment, TestSafetyError


PASSWORD = "fictional-process-proof-password"
OWNER_MARKER = "delvane-owned-persistence-proof-v1"


def child(root, port, mode):
    root=Path(root).resolve()
    if (root.parent != Path(tempfile.gettempdir()).resolve()
            or not root.name.startswith('delvane-persistence-proof-')
            or (root/'proof-owner.txt').read_text()!=OWNER_MARKER):
        raise RuntimeError('Child proof root is not an owned temporary directory')
    token=_ACTIVE_ROOT.set(root)
    password=json.loads(sys.stdin.readline())['password']
    try:
        if mode=='persistent':
            from persistent_development import PersistentDevelopment
            from run_persistent_development_workspace import serve
            serve(PersistentDevelopment(_test_parent=root),password,port=port,_stop_stream=sys.stdin)
        else:
            import uvicorn  # Import library before installing subprocess guards.
            from run_development_workspace import prepare_workspace, serve_application
            with IsolatedEnvironment() as storage:
                import app
                storage.protect_app(app)
                prepare_workspace(app,storage,password)
                serve_application(app,port=port,_stop_stream=sys.stdin)
    finally:
        _ACTIVE_ROOT.reset(token)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):
        raise RuntimeError('Proof refuses redirects')


class Client:
    def __init__(self,port):
        self.origin=f'http://127.0.0.1:{port}'
        self.csrf=None
        self.opener=urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect(),urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def request(self,path,body=None,method=None):
        assert path.startswith('/api/') or path=='/health/live'
        headers={}
        if self.csrf: headers['X-Rosa-CSRF']=self.csrf
        data=None
        if body is not None:
            data=json.dumps(body).encode();headers['Content-Type']='application/json'
        request=urllib.request.Request(self.origin+path,data=data,headers=headers,method=method)
        try:
            with self.opener.open(request,timeout=2) as response:
                return response.status,json.load(response)
        except urllib.error.HTTPError as error:
            return error.code,json.load(error)

    def login(self):
        status,payload=self.request('/api/login',{'email':'owner@workspace.invalid','password':PASSWORD})
        assert status==200
        self.csrf=payload['csrf_token']


@contextmanager
def server(root,port,mode,client):
    environment=dict(os.environ)
    # Poisoned *fictional* config must not redirect either guarded launcher.
    environment.update(ROSA_DATABASE_URL='postgresql://fictional.invalid/never-connect',
                       ROSA_APP_ENV='production',ROSA_CHANNEX_API_KEY='fictional-not-a-real-key',
                       OPENAI_API_KEY='fictional-not-a-real-key')
    with tempfile.TemporaryFile(mode='w+',encoding='utf-8') as log:
        process=subprocess.Popen([sys.executable,'-B',str(Path(__file__).resolve()),'--child-root',str(root),'--port',str(port),'--mode',mode],
                                 stdin=subprocess.PIPE,stdout=log,stderr=subprocess.STDOUT,text=True,env=environment)
        try:
            process.stdin.write(json.dumps({'password':PASSWORD})+'\n');process.stdin.flush()
            deadline=time.monotonic()+30
            while time.monotonic()<deadline:
                if process.poll() is not None:
                    log.seek(0);raise RuntimeError('Guarded child stopped before startup: '+log.read())
                try:
                    status,marker=client.request('/api/development/workspace')
                    if status==200 and marker.get('isolated') is True and marker.get('mode')==mode:
                        break
                except (OSError,urllib.error.URLError): pass
                time.sleep(.1)
            else: raise RuntimeError('Guarded server startup timed out')
            yield marker
        finally:
            if process.poll() is None:
                process.stdin.write('stop\n');process.stdin.flush()
                try: process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    process.terminate();process.wait(timeout=10)
                    raise RuntimeError('Child did not stop gracefully')
            process.stdin.close()
            if process.returncode:
                log.seek(0);raise RuntimeError('Guarded child failed: '+log.read())


def proof():
    with tempfile.TemporaryDirectory(prefix='delvane-persistence-proof-') as directory:
        root=Path(directory).resolve()
        (root/'proof-owner.txt').write_text(OWNER_MARKER)
        with socket.socket() as probe:
            probe.bind(('127.0.0.1',0));port=probe.getsockname()[1]
        client=Client(port)
        with server(root,port,'persistent',client) as first:
            client.login()
            day=date.fromisoformat(first['date'])+timedelta(days=800)
            payload={'property_id':'prop_flora','guest_name':'Fictional Restart Proof','source':'Direct','arrival_date':str(day),'departure_date':str(day+timedelta(days=2)),'guest_count':1,'total_huf':123456,'arrival_time':'18:30','special_requests':['Fictional cot']}
            status,result=client.request('/api/reservations',payload);assert status==200
            rid=result['id']
            assert client.request(f'/api/reservations/{rid}/notes',{'body':'Fictional persisted note'})[0]==200
            status,detail=client.request(f'/api/reservations/{rid}/detail');assert status==200
            assert detail['reservation']['guest_name']==payload['guest_name']
            status,links=client.request(f'/api/reservations/{rid}/guest-checkin-links');assert status==200
            token=links['links'][0]['url'].rsplit('/',1)[-1]
            assert client.request(f'/api/public/checkin/{token}',{'full_name':'Fictional Restart Proof','date_of_birth':'2000-01-02','nationality':'HUN','document_type':'passport','document_number':'FICTIONAL-ONLY','guest_confirmed':True,'address':'Fictional encrypted address'})[0]==200
            status,member=client.request('/api/team/members',{'full_name':'Fictional Proof Cleaner','email':'proof@workspace.invalid','role':'cleaner'});assert status==200
            member_id=member['member_id']
            status,work=client.request('/api/work-tasks',{'property_id':'prop_flora','title':'Fictional Proof Task','scheduled_date':first['date'],'assigned_to':member_id});assert status==200
            task_id=work['id']
            assert client.request('/api/client/environment')[0]==404
            assert client.request('/api/demo/reset',{},'POST')[0]==404
        assert (root/'.development/persistent/workspace.db').is_file()
        with server(root,port,'persistent',client) as second:
            assert first['workspace_id']==second['workspace_id']
            assert client.request('/api/me')[0]==200  # Existing server-side session survives.
            client.login()
            status,detail=client.request(f'/api/reservations/{rid}/detail');assert status==200
            for field in ['guest_name','arrival_date','departure_date','guest_count','total_huf','arrival_time']:
                assert detail['reservation'][field]==payload[field]
            assert detail['reservation']['registration_status']=='pending'
            assert any(x['body']=='Fictional persisted note' for x in detail['notes'])
            status,sensitive=client.request(f'/api/registration/{rid}/sensitive');assert status==200
            assert any(x['sensitive'] and x['sensitive']['address']=='Fictional encrypted address' for x in sensitive)
            status,team=client.request('/api/team/overview');assert status==200
            assert any(x['id']==member_id for x in team['members'])
            assert any(x['id']==task_id and x['assigned_to']==member_id for x in team['workload'])
            client.csrf=None
            assert client.request(f'/api/reservations/{rid}/notes',{'body':'Must be refused'})[0]==403
        print('PASS: two independent persistent backend processes retained reservation details, guests, encrypted data, staff, assignment, workspace identity and session; CSRF remains enforced.')
        disposable=Client(port)
        with server(root,port,'disposable',disposable) as fresh:
            disposable.login()
            status,new=disposable.request('/api/reservations',payload);assert status==200
            discarded=new['id']
        assert not list(root.glob('delvane-tests-*'))
        with server(root,port,'disposable',disposable) as next_fresh:
            assert fresh['workspace_id']!=next_fresh['workspace_id']
            disposable.login()
            assert disposable.request(f'/api/reservations/{discarded}/detail')[0]==404
        assert not list(root.glob('delvane-tests-*'))
        print('PASS: disposable backend processes use fresh IDs/data and remove their own temporary databases.')
        print('PASS: proof used only owned temporary storage and ephemeral loopback; inherited fictional production configuration was ignored. No operational/staging database was opened.')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--child-root',help=argparse.SUPPRESS)
    parser.add_argument('--port',type=int,help=argparse.SUPPRESS)
    parser.add_argument('--mode',choices=['persistent','disposable'],help=argparse.SUPPRESS)
    args=parser.parse_args()
    if args.child_root:
        child(args.child_root,args.port,args.mode)
    else:
        proof()
