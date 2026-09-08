#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, re
from datetime import datetime, timezone
from pathlib import Path
from import_revalida import pdf_text, parse_key, parse_questions

def parse_edition(raw: str):
    m=re.fullmatch(r'(20\d{2})[/_-]([12])', raw.strip())
    if not m: raise SystemExit('edição inválida; use 2025/1')
    y,h=int(m.group(1)),int(m.group(2))
    return y,h,f'{y}/{h}',f'revalida-{y}-{h}'

def cutoff_for(y,h):
    return {(2026,1):59,(2025,2):61}.get((y,h))

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--pack',type=Path,default=Path('content/packs/latest.json'))
    ap.add_argument('--edition',required=True)
    ap.add_argument('--exam',type=Path,required=True)
    ap.add_argument('--key',type=Path,required=True)
    ap.add_argument('--staging-dir',type=Path,default=Path('importer/staging'))
    ap.add_argument('--remove-demo',action='store_true')
    args=ap.parse_args()
    y,h,label,exam_id=parse_edition(args.edition)
    for p,name in ((args.exam,'caderno'),(args.key,'gabarito')):
        if not p.exists(): raise SystemExit(f'{name} não encontrado: {p}')
    args.staging_dir.mkdir(parents=True,exist_ok=True)
    report_path=args.staging_dir/f'{exam_id}-local-report.json'
    pack=json.loads(args.pack.read_text(encoding='utf-8'))
    qtext=pdf_text(args.exam); ktext=pdf_text(args.key)
    parsed=parse_questions(qtext); key=parse_key(ktext)
    high=sum(1 for _,_,opts,conf in parsed if conf=='high' and len(opts)==4)
    nums={n for n,*_ in parsed}
    report={
      'edition':label,'exam_file':str(args.exam),'key_file':str(args.key),
      'parsed_total':len(parsed),'high_confidence':high,'key_items':len(key),
      'published':False,'generated_at':datetime.now(timezone.utc).isoformat()
    }
    ok=(len(parsed)==100 and high==100 and len(key)>=95 and nums==set(range(1,101)))
    if not ok:
        report['error']='validação estrutural falhou; pack preservado'
        report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
        print(f"FALHOU: parsed={len(parsed)} high={high} key={len(key)}")
        raise SystemExit(2)
    header=ktext[:5000].lower(); key_final=('gabarito definitivo' in header or 'gabarito final' in header or 'definit' in args.key.name.lower() or 'final' in args.key.name.lower())
    qs=[]
    for n,stem,opts,_ in parsed:
        ans=key.get(n)
        qs.append({
          'id':f'{exam_id}-q{n:03d}','examId':exam_id,'number':n,'source':'INEP','year':y,'edition':label,
          'type':'objective','area':'Não classificada','specialty':None,'topic':None,'stem':stem,
          'options':[{'id':f'{exam_id}-q{n:03d}-{a}','label':a,'text':t} for a,t in opts],
          'correctOption':None if ans=='ANULADA' else ans,'explanation':None,'optionExplanations':None,'keyPoint':None,
          'status':'annulled' if ans=='ANULADA' else ('final' if key_final and ans else ('preliminary' if ans else 'awaiting_key')),
          'officialSourceURL':None
        })
    exams={e['id']:e for e in pack.get('exams',[])}
    if (y,h)==(2025,1): fmt,disc='objective100_discursive5',5
    else: fmt,disc='objective100',0
    exams[exam_id]={
      'id':exam_id,'name':f'Revalida {label}','year':y,'edition':label,'board':'INEP','formatVersion':fmt,
      'objectiveQuestions':100,'discursiveQuestions':disc,'durationMinutes':300,'officialCutoff':cutoff_for(y,h),
      'examDate':None,'sourceURL':None
    }
    pack['exams']=list(exams.values())
    qmap={q['id']:q for q in pack.get('questions',[])}
    for q in qs:qmap[q['id']]=q
    pack['questions']=list(qmap.values())
    if args.remove_demo:
        before=len(pack['questions'])
        pack['questions']=[q for q in pack['questions'] if q.get('source')!='DEMO' and q.get('status')!='demo']
        print(f"DEMO removido: {before-len(pack['questions'])}")
    pack['version']=int(pack.get('version',0))+1
    pack['generatedAt']=datetime.now(timezone.utc).isoformat()
    args.pack.write_text(json.dumps(pack,ensure_ascii=False,indent=2),encoding='utf-8')
    report['published']=True;report['key_status']='final' if key_final else 'preliminary'
    report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f"OK {label}: 100 questões | gabarito {report['key_status']} | pack v{pack['version']} | total {len(pack['questions'])}")

if __name__=='__main__': main()
