#!/usr/bin/env python3
"""Tenta publicar automaticamente a edição objetiva mais nova detectada.

Fail-closed: só cria um novo pack se o caderno for extraído com exatamente 100
questões de 4 alternativas e o gabarito tiver cobertura suficiente. Caso contrário,
o banco publicado permanece intacto e um relatório é salvo em staging.
"""
from __future__ import annotations
import argparse, json, re, tempfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse
import requests

from import_revalida import pdf_text, parse_key, parse_questions

EDITION_RE = re.compile(r'(?<!\d)(20\d{2})[\s_./-]*([12])(?!\d)')

def edition_from(item: dict):
    hay = f"{item.get('label','')} {item.get('url','')}"
    m = EDITION_RE.search(hay)
    return (int(m.group(1)), int(m.group(2))) if m else None

def kind(item: dict):
    s=f"{item.get('label','')} {item.get('url','')}".lower()
    if 'gabarito' in s: return 'key_final' if ('definit' in s or 'final' in s) else 'key_prelim'
    if ('caderno' in s or 'prova' in s) and 'ampliad' not in s and 'libras' not in s: return 'exam'
    return None

def choose(items, target):
    same=[i for i in items if edition_from(i)==target]
    exams=[i for i in same if kind(i)=='exam']
    finals=[i for i in same if kind(i)=='key_final']
    prelim=[i for i in same if kind(i)=='key_prelim']
    def score_exam(i):
        s=(i.get('label','')+' '+i.get('url','')).lower()
        return (10 if 'caderno_1' in s or 'caderno 1' in s or 'caderno 01' in s else 0) - (5 if 'adapt' in s else 0)
    return (max(exams,key=score_exam) if exams else None, (finals[0] if finals else (prelim[0] if prelim else None)))

def download(url: str, path: Path):
    r=requests.get(url,timeout=60,headers={'User-Agent':'RevalidaOS-content-watcher/1.0'});r.raise_for_status();path.write_bytes(r.content)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--discovered',type=Path,required=True);ap.add_argument('--pack',type=Path,required=True);ap.add_argument('--staging-dir',type=Path,default=Path('importer/staging'));args=ap.parse_args()
    discovered=json.loads(args.discovered.read_text(encoding='utf-8'))['items']; base=json.loads(args.pack.read_text(encoding='utf-8'))

    # Um exame pode existir no pack apenas como metadado/calendário antes de o caderno
    # ser publicado (ex.: Revalida 2026/2). Só consideramos uma edição realmente
    # importada quando o pack já contém o número esperado de questões objetivas INEP.
    question_counts={}
    for q in base.get('questions',[]):
        if q.get('source')=='INEP' and q.get('type')=='objective' and q.get('examId'):
            question_counts[q['examId']]=question_counts.get(q['examId'],0)+1
    existing=set()
    for e in base.get('exams',[]):
        edition=str(e.get('edition',''))
        expected=int(e.get('objectiveQuestions') or 0)
        if e.get('year') and '/' in edition and expected>0 and question_counts.get(e.get('id'),0)>=expected:
            existing.add((int(e['year']),int(edition.split('/')[-1])))

    editions=sorted({e for i in discovered if (e:=edition_from(i))},reverse=True)
    targets=[e for e in editions if e not in existing]
    args.staging_dir.mkdir(parents=True,exist_ok=True)
    if not targets:
        print('nenhuma edição nova completa detectada'); return
    target=targets[0]; exam_item,key_item=choose(discovered,target)
    if not exam_item or not key_item:
        print(f'edição {target} detectada, mas ainda sem par caderno+gabarito'); return
    with tempfile.TemporaryDirectory() as td:
        ep=Path(td)/'exam.pdf';kp=Path(td)/'key.pdf';download(exam_item['url'],ep);download(key_item['url'],kp)
        parsed=parse_questions(pdf_text(ep)); key=parse_key(pdf_text(kp))
    clean=[];review=[]
    image_terms=('figura','imagem','radiografia','tomografia','eletrocardiograma','ecg','gráfico','tabela','ultrassonografia')
    year,half=target; exam_id=f'revalida-{year}-{half}'
    key_final=kind(key_item)=='key_final'
    for n,stem,opts,confidence in parsed:
        ans=key.get(n)
        item={'id':f'{exam_id}-q{n:03d}','examId':exam_id,'number':n,'source':'INEP','year':year,'edition':f'{year}/{half}','type':'objective','area':'Não classificada','specialty':None,'topic':None,'stem':stem,'options':[{'id':f'{exam_id}-q{n:03d}-{l}','label':l,'text':t} for l,t in opts],'correctOption':None if ans=='ANULADA' else ans,'explanation':None,'optionExplanations':None,'keyPoint':None,'status':'annulled' if ans=='ANULADA' else ('final' if key_final and ans else ('preliminary' if ans else 'awaiting_key')),'officialSourceURL':exam_item['url']}
        has_media=any(t in stem.lower() for t in image_terms)
        (clean if confidence=='high' and len(opts)==4 and not has_media else review).append(item)
    report={'edition':f'{year}/{half}','exam_url':exam_item['url'],'key_url':key_item['url'],'parsed_total':len(parsed),'safe_text_questions':len(clean),'needs_review':len(review),'key_items':len(key),'published':False}
    report_path=args.staging_dir/f'{exam_id}-report.json'
    # Publica a prova inteira somente se a extração estrutural estiver completa. Questões com mídia
    # podem existir, mas devem ter texto/opções íntegros; o termo de mídia apenas gera relatório.
    structural_ok = len(parsed)==100 and all(len(opts)==4 and confidence=='high' for _,_,opts,confidence in parsed) and len(key)>=95
    if not structural_ok:
        report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(report,ensure_ascii=False));return
    all_questions=[]
    for n,stem,opts,confidence in parsed:
        ans=key.get(n)
        all_questions.append({'id':f'{exam_id}-q{n:03d}','examId':exam_id,'number':n,'source':'INEP','year':year,'edition':f'{year}/{half}','type':'objective','area':'Não classificada','specialty':None,'topic':None,'stem':stem,'options':[{'id':f'{exam_id}-q{n:03d}-{l}','label':l,'text':t} for l,t in opts],'correctOption':None if ans=='ANULADA' else ans,'explanation':None,'optionExplanations':None,'keyPoint':None,'status':'annulled' if ans=='ANULADA' else ('final' if key_final and ans else ('preliminary' if ans else 'awaiting_key')),'officialSourceURL':exam_item['url']})
    base['exams']=[e for e in base.get('exams',[]) if e['id']!=exam_id]+[{'id':exam_id,'name':f'Revalida {year}/{half}','year':year,'edition':f'{year}/{half}','board':'INEP','formatVersion':'objective100','objectiveQuestions':100,'discursiveQuestions':0,'durationMinutes':300,'officialCutoff':None,'examDate':None,'sourceURL':exam_item['url']}]
    existing_q={q['id']:q for q in base.get('questions',[])}
    for q in all_questions:existing_q[q['id']]=q
    base['questions']=list(existing_q.values());base['version']=int(base.get('version',0))+1;base['generatedAt']=datetime.now(timezone.utc).isoformat()
    news_id=f'{exam_id}-available'
    base['news']=[n for n in base.get('news',[]) if n['id']!=news_id]+[{'id':news_id,'title':f'Revalida {year}/{half} disponível no banco','body':'Caderno e gabarito oficiais detectados e importados automaticamente. Questões com imagens/tabelas devem ser conferidas no ciclo de enriquecimento.','category':'Banco de questões','priority':'high','publishedAt':datetime.now(timezone.utc).date().isoformat(),'eventDate':None,'endDate':None,'sourceURL':exam_item['url'],'isRead':False}]
    args.pack.write_text(json.dumps(base,ensure_ascii=False,indent=2),encoding='utf-8');report['published']=True;report['new_version']=base['version'];report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(report,ensure_ascii=False))
if __name__=='__main__':main()
