#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--pack',type=Path,required=True);ap.add_argument('--manifest',type=Path,required=True);ap.add_argument('--relative-pack',default=None);args=ap.parse_args()
    data=args.pack.read_bytes(); pack=json.loads(data)
    manifest={'version':int(pack['version']),'generatedAt':pack['generatedAt'],'packURL':args.relative_pack or str(args.pack.name),'sha256':hashlib.sha256(data).hexdigest(),'notes':f"{len(pack.get('questions',[]))} questões"}
    args.manifest.parent.mkdir(parents=True,exist_ok=True);args.manifest.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print(args.manifest)
if __name__=='__main__': main()
