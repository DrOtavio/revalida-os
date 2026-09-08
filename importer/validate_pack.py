#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, sys
from pathlib import Path

def main():
    ap=argparse.ArgumentParser();ap.add_argument('pack',type=Path);args=ap.parse_args();p=json.loads(args.pack.read_text(encoding='utf-8'));errors=[]
    qids=[q['id'] for q in p.get('questions',[])];eids=[e['id'] for e in p.get('exams',[])];nids=[n['id'] for n in p.get('news',[])]
    for name,ids in [('question',qids),('exam',eids),('news',nids)]:
        if len(ids)!=len(set(ids)):errors.append(f'{name}: IDs duplicados')
    exams=set(eids)
    for q in p.get('questions',[]):
        if q.get('examId') and q['examId'] not in exams:errors.append(f"{q['id']}: examId inexistente")
        if q.get('type')=='objective':
            labels=[o.get('label') for o in q.get('options',[])]
            if labels and labels!=['A','B','C','D']:errors.append(f"{q['id']}: alternativas inválidas {labels}")
            if q.get('correctOption') not in (None,'A','B','C','D'):errors.append(f"{q['id']}: gabarito inválido")
    if errors:
        print('\n'.join(errors));sys.exit(1)
    print(f"OK v{p.get('version')} — {len(qids)} questões, {len(eids)} provas, {len(nids)} notícias")
if __name__=='__main__':main()
