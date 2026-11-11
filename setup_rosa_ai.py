from __future__ import annotations
import argparse
import getpass
import json
import os
from pathlib import Path
import urllib.error
import urllib.request

ROOT=Path(__file__).resolve().parent
def stable_env_path():
    if os.name=='nt' and os.getenv('LOCALAPPDATA','').strip():
        return Path(os.environ['LOCALAPPDATA'])/'Rosa'/'.env.local'
    xdg=os.getenv('XDG_CONFIG_HOME','').strip()
    return (Path(xdg)/'rosa'/'.env.local') if xdg else ROOT/'.env.local'

ENV=stable_env_path()
MODEL='gpt-5.6-luna'

def write_config(key:str):
    ENV.parent.mkdir(parents=True,exist_ok=True)
    updates={
        'ROSA_AI_PROVIDER':'openai',
        'ROSA_OPENAI_API_KEY':key,
        'ROSA_OPENAI_MODEL':MODEL,
        'ROSA_OPENAI_REASONING_EFFORT':'none',
        'ROSA_AI_TIMEOUT_SECONDS':'25',
    }
    lines=ENV.read_text(encoding='utf-8').splitlines() if ENV.exists() else []
    output=[]
    for raw in lines:
        stripped=raw.strip()
        name=stripped.split('=',1)[0].strip() if '=' in stripped and not stripped.startswith('#') else ''
        if name in updates:
            output.append(f'{name}={updates.pop(name)}')
        else:
            output.append(raw)
    if output and output[-1].strip(): output.append('')
    if updates:
        output.append('# Rosa local-development AI configuration. DO NOT SHARE OR UPLOAD THIS FILE.')
        output.extend(f'{name}={value}' for name,value in updates.items())
    ENV.write_text('\n'.join(output).rstrip()+'\n',encoding='utf-8')

def test_key(key:str):
    payload=json.dumps({
        'model':MODEL,
        'reasoning':{'effort':'none'},
        'max_output_tokens':24,
        'input':'Reply with exactly: OK'
    }).encode('utf-8')
    req=urllib.request.Request(
        'https://api.openai.com/v1/responses',
        data=payload,
        headers={'Authorization':f'Bearer {key}','Content-Type':'application/json'},
        method='POST'
    )
    try:
        with urllib.request.urlopen(req,timeout=25) as resp:
            data=json.loads(resp.read().decode('utf-8'))
        text=''
        for item in data.get('output',[]):
            for c in item.get('content',[]):
                if c.get('type') in {'output_text','text'}:
                    text += c.get('text','')
        return True, (text.strip() or 'Connected')
    except urllib.error.HTTPError as exc:
        detail=''
        try:
            body=json.loads(exc.read().decode('utf-8'))
            detail=(body.get('error') or {}).get('message','')
        except Exception:
            pass
        return False, f'HTTP {exc.code}' + (f': {detail}' if detail else '')
    except Exception as exc:
        return False, f'{type(exc).__name__}: {exc}'

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--disable',action='store_true')
    args=ap.parse_args()
    if args.disable:
        if ENV.exists():
            ai_names={'ROSA_AI_PROVIDER','ROSA_OPENAI_API_KEY','ROSA_OPENAI_MODEL','ROSA_OPENAI_REASONING_EFFORT','ROSA_AI_TIMEOUT_SECONDS'}
            lines=[]
            for raw in ENV.read_text(encoding='utf-8').splitlines():
                stripped=raw.strip(); name=stripped.split('=',1)[0].strip() if '=' in stripped and not stripped.startswith('#') else ''
                if name not in ai_names: lines.append(raw)
            ENV.write_text('\n'.join(lines).rstrip()+'\n',encoding='utf-8')
        print('Luna fallback disabled locally. Rosa remains fully usable with the local-first database and operations engine.')
        return
    print('\nROSA V2.8.3 — Optional GPT-5.6 Luna fallback setup')
    print('Rosa stays LOCAL-FIRST. This key is used only when the local router cannot answer confidently.')
    print('Database facts, exact operational lookups, missing facts and governed actions never call Luna.')
    print("The key is stored in Rosa's private persistent configuration on this computer.")
    print('Do NOT paste your API key into ChatGPT or send .env.local to anyone.\n')
    key=getpass.getpass('Paste your OpenAI API key (hidden): ').strip()
    if len(key)<20:
        raise SystemExit('That does not look like a complete API key. Nothing was saved.')
    write_config(key)
    print('\nSaved local AI configuration. Testing GPT-5.6 Luna...')
    ok,msg=test_key(key)
    if ok:
        print(f'CONNECTED — Luna replied: {msg}')
        print('\nNow close any running Rosa window/server and run START_ROSA.bat.')
    else:
        print(f'\nThe key was saved, but the connection test failed: {msg}')
        print('Common causes: API billing is not funded yet, the key has insufficient permissions, or Luna is disabled for the project.')
        print('Fix the API account setting, then run SETUP_ROSA_AI.bat again.')

if __name__=='__main__':
    main()
