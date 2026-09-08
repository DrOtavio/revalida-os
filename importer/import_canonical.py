#!/usr/bin/env python3
from __future__ import annotations
import argparse, json
from datetime import datetime, timezone
from pathlib import Path
from canonical_format import read_questions, read_answer_key


def cutoff_for(y,h): return {(2026,1):59,(2025,2):61}.get((y,h))

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--questions',type=Path,required=True)
    ap.add_argument('--key',type=Path,required=True)
    ap.add_argument('--pack',type=Path,default=Path('content/packs/latest.json'))
    ap.add_argument('--remove-demo',action='store_true')
    args=ap.parse_args()
    meta,qs=read_questions(args.questions); kmeta,key=read_answer_key(args.key)
    y=int(meta['YEAR']); label=meta['EDITION']; h=int(label.split('/')[1]); exam_id=meta['EXAM_ID']
    status=kmeta.get('STATUS','FINAL').upper(); key_final=status=='FINAL'
    pack=json.loads(args.pack.read_text(encoding='utf-8'))
    exams={e['id']:e for e in pack.get('exams',[])}
    exams[exam_id]={
        'id':exam_id,'name':f'Revalida {label}','year':y,'edition':label,'board':'INEP',
        'formatVersion':'objective100_discursive5' if (y,h)==(2025,1) else 'objective100',
        'objectiveQuestions':100,'discursiveQuestions':5 if (y,h)==(2025,1) else 0,
        'durationMinutes':int(meta.get('TIME_MINUTES','300')),'officialCutoff':cutoff_for(y,h),
        'examDate':None,'sourceURL':None,
    }
    pack['exams']=list(exams.values())
    qmap={q['id']:q for q in pack.get('questions',[])}
    for q in qs:
        ans=key[q.number]
        qid=f'{exam_id}-q{q.number:03d}'
        qmap[qid]={
            'id':qid,'examId':exam_id,'number':q.number,'source':'INEP','year':y,'edition':label,'type':'objective',
            'area':'Não classificada','specialty':None,'topic':None,'stem':q.text,
            'options':[{'id':f'{qid}-{a}','label':a,'text':q.options[a]} for a in 'ABCD'],
            'correctOption':None if ans=='ANNULLED' else ans,'explanation':None,'optionExplanations':None,'keyPoint':None,
            'status':'annulled' if ans=='ANNULLED' else ('final' if key_final else 'preliminary'),
            'officialSourceURL':None,'mediaStatus':'needs_review' if q.images else 'none','media':q.images,
        }
    pack['questions']=list(qmap.values())
    if args.remove_demo:
        pack['questions']=[q for q in pack['questions'] if q.get('source')!='DEMO' and q.get('status')!='demo']
    pack['version']=int(pack.get('version',0))+1
    pack['generatedAt']=datetime.now(timezone.utc).isoformat()
    args.pack.write_text(json.dumps(pack,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f'OK canonical import {label}: pack v{pack["version"]}, total={len(pack["questions"])}')

if __name__=='__main__': main()
