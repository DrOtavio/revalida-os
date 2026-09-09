#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path


def run(cmd: list[str]) -> None:
    print('+', ' '.join(cmd), flush=True)
    subprocess.run(cmd, check=True)


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--sources-root', type=Path, default=Path('sources/revalida'))
    ap.add_argument('--pack', type=Path, default=Path('content/packs/latest.json'))
    ap.add_argument('--remove-demo', action='store_true')
    args=ap.parse_args()

    folders=[]
    for folder in sorted(args.sources_root.iterdir() if args.sources_root.exists() else []):
        if not folder.is_dir():
            continue
        required=[folder/'questions.txt', folder/'answer_key.txt', folder/'metadata.json', folder/'explanations.json']
        if all(p.exists() for p in required):
            folders.append(folder)
        elif any(p.exists() for p in required):
            missing=[p.name for p in required if not p.exists()]
            print(f'SKIP incompleto {folder.name}: faltam {", ".join(missing)}')

    if not folders:
        raise SystemExit('Nenhuma edição completa encontrada')

    original=json.loads(args.pack.read_text(encoding='utf-8'))
    start_version=int(original.get('version',0))

    for folder in folders:
        report=folder/'validation_report.json'
        run([sys.executable,'importer/validate_canonical.py',
             '--questions',str(folder/'questions.txt'),
             '--key',str(folder/'answer_key.txt'),
             '--media-root',str(folder),
             '--json-report',str(report)])
        cmd=[sys.executable,'importer/import_canonical.py',
             '--questions',str(folder/'questions.txt'),
             '--key',str(folder/'answer_key.txt'),
             '--metadata',str(folder/'metadata.json'),
             '--explanations',str(folder/'explanations.json'),
             '--pack',str(args.pack),
             '--no-version-bump']
        if args.remove_demo:
            cmd.append('--remove-demo')
        run(cmd)

    pack=json.loads(args.pack.read_text(encoding='utf-8'))
    pack['version']=start_version+1
    pack['generatedAt']=datetime.now(timezone.utc).isoformat()
    args.pack.write_text(json.dumps(pack,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f'OK banco total: edições={len(folders)} pack=v{pack["version"]} questões={len(pack.get("questions",[]))}')

if __name__=='__main__':
    main()
