#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, re
from pathlib import Path
from canonical_format import read_questions, read_answer_key


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--questions',type=Path,required=True)
    ap.add_argument('--key',type=Path,required=True)
    ap.add_argument('--media-root',type=Path)
    ap.add_argument('--json-report',type=Path)
    args=ap.parse_args()
    meta,qs=read_questions(args.questions)
    kmeta,key=read_answer_key(args.key)
    errors=[]; warnings=[]
    nums=[q.number for q in qs]
    if nums != list(range(1,101)):
        errors.append(f'Numeração inválida: encontrados {len(nums)} itens; faltantes={sorted(set(range(1,101))-set(nums))}')
    for q in qs:
        if q.parse_status!='OK': errors.append(f'Q{q.number:03d}: PARSE_STATUS={q.parse_status}')
        if len(q.text.strip())<10: errors.append(f'Q{q.number:03d}: enunciado vazio/curto')
        for label in 'ABCD':
            if len(q.options.get(label,'').strip())<1: errors.append(f'Q{q.number:03d}: OPTION_{label} vazio')
        for image in q.images:
            if args.media_root and not (args.media_root/image).exists(): errors.append(f'Q{q.number:03d}: imagem ausente {image}')
    if set(key)!=set(range(1,101)):
        errors.append(f'Gabarito deve conter Q001-Q100; itens={len(key)}')
    for n,a in key.items():
        if a not in {'A','B','C','D','ANNULLED'}: errors.append(f'Q{n:03d}: gabarito inválido {a}')
    if meta.get('EDITION') != kmeta.get('EDITION'): errors.append('EDITION divergente entre questions.txt e answer_key.txt')
    status='PASS' if not errors else 'FAIL'
    report={'status':status,'questions':len(qs),'answers':len(key),'errors':errors,'warnings':warnings,'metadata':meta,'keyMetadata':kmeta}
    if args.json_report:
        args.json_report.parent.mkdir(parents=True,exist_ok=True)
        args.json_report.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f'{status}: questions={len(qs)} answers={len(key)} errors={len(errors)}')
    for e in errors[:50]: print('ERROR',e)
    raise SystemExit(0 if status=='PASS' else 2)

if __name__=='__main__': main()
