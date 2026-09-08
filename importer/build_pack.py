#!/usr/bin/env python3
from __future__ import annotations
import argparse, json
from datetime import datetime, timezone
from pathlib import Path

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--base',type=Path,required=True);ap.add_argument('--staged',type=Path,required=True);ap.add_argument('--version',type=int,required=True);ap.add_argument('--output',type=Path,required=True);args=ap.parse_args()
    base=json.loads(args.base.read_text(encoding='utf-8')); staged=json.loads(args.staged.read_text(encoding='utf-8'))
    existing={q['id']:q for q in base.get('questions',[])}
    for q in staged.get('questions',[]): existing[q['id']]=q
    base['questions']=list(existing.values());base['version']=args.version;base['generatedAt']=datetime.now(timezone.utc).isoformat()
    args.output.write_text(json.dumps(base,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f"pack v{args.version}: {len(base['questions'])} questões")
if __name__=='__main__': main()
