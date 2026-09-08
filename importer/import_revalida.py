#!/usr/bin/env python3
"""Importador semiautomático de caderno/gabarito do Revalida.

Uso:
  python import_revalida.py --exam revalida.pdf --key gabarito.pdf \
      --exam-id revalida-2026-2 --year 2026 --edition 2026/2 --output staged.json

O parser é deliberadamente conservador: se a estrutura não puder ser interpretada
com confiança, a questão vai para `needs_review` em vez de ser publicada errada.
"""
from __future__ import annotations
import argparse, json, re, shutil, subprocess, tempfile
from pathlib import Path
from pypdf import PdfReader

Q_RE=re.compile(r'(?im)^\s*(?:QUEST[ÃA]O|QUESTÃO)\s*(\d{1,3})\s*[\.:\-]?\s*')
OPT_RE=re.compile(r'(?ms)^\s*([A-D])\s*[\)\.\-]\s*(.*?)(?=^\s*[A-D]\s*[\)\.\-]\s*|\Z)')
KEY_RE=re.compile(r'(?im)(\d{1,3})\s*[-\.:]?\s*([A-D]|ANULAD[AO])\b')

def _pypdf_text(path: Path) -> str:
    return "\n".join((p.extract_text() or "") for p in PdfReader(str(path)).pages)

def _pymupdf_text(path: Path) -> str:
    try:
        import fitz  # PyMuPDF
    except Exception:
        return ""
    try:
        doc = fitz.open(str(path))
        return "\n".join(page.get_text("text", sort=True) or "" for page in doc)
    except Exception:
        return ""

def _pdftotext_text(path: Path) -> str:
    exe = shutil.which("pdftotext")
    if not exe:
        return ""
    try:
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "out.txt"
            subprocess.run([exe, "-layout", "-enc", "UTF-8", str(path), str(out)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
            return out.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return ""

def _text_score(text: str) -> tuple[int, int, int]:
    # Prioriza extrações que reconhecem os cabeçalhos das questões, depois A-D
    # e por fim quantidade de texto útil. Isso ajuda com PDFs oficiais que usam
    # fontes incorporadas que alguns extratores interpretam mal.
    q = len(Q_RE.findall(text))
    opts = len(re.findall(r'(?im)^\s*[A-D]\s*[\)\.\-]', text))
    letters = len(re.findall(r'[A-Za-zÀ-ÿ]{3,}', text))
    return (q, opts, letters)

def pdf_text(path: Path) -> str:
    candidates = [_pymupdf_text(path), _pdftotext_text(path), _pypdf_text(path)]
    candidates = [text for text in candidates if text.strip()]
    return max(candidates, key=_text_score) if candidates else ""

def parse_key(text: str) -> dict[int,str]:
    out={}
    for n,a in KEY_RE.findall(text): out[int(n)]=a.upper()[0] if a.upper().startswith(tuple('ABCD')) else 'ANULADA'
    return out

def parse_questions(text: str):
    matches=list(Q_RE.finditer(text)); out=[]
    for i,m in enumerate(matches):
        n=int(m.group(1)); chunk=text[m.end():matches[i+1].start() if i+1<len(matches) else len(text)].strip()
        opts=list(OPT_RE.finditer(chunk))
        if len(opts)>=4:
            stem=chunk[:opts[0].start()].strip()
            options=[(o.group(1),re.sub(r'\s+',' ',o.group(2)).strip()) for o in opts[:4]]
            confidence='high' if len(stem)>30 and all(len(t)>2 for _,t in options) else 'low'
        else:
            stem=chunk; options=[]; confidence='low'
        out.append((n,stem,options,confidence))
    return out

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--exam',type=Path,required=True);ap.add_argument('--key',type=Path)
    ap.add_argument('--exam-id',required=True);ap.add_argument('--year',type=int,required=True);ap.add_argument('--edition',required=True)
    ap.add_argument('--output',type=Path,required=True); args=ap.parse_args()
    qtext=pdf_text(args.exam); key=parse_key(pdf_text(args.key)) if args.key else {}
    questions=[]; needs=[]
    for n,stem,opts,confidence in parse_questions(qtext):
        answer=key.get(n)
        item={
          'id':f'{args.exam_id}-q{n:03d}','examId':args.exam_id,'number':n,'source':'INEP','year':args.year,'edition':args.edition,
          'type':'objective','area':'Não classificada','specialty':None,'topic':None,'stem':stem,
          'options':[{'id':f'{args.exam_id}-q{n:03d}-{l}','label':l,'text':t} for l,t in opts],
          'correctOption':None if answer=='ANULADA' else answer,'explanation':None,'optionExplanations':None,'keyPoint':None,
          'status':'annulled' if answer=='ANULADA' else ('preliminary' if answer else 'awaiting_key'),'officialSourceURL':None
        }
        if confidence=='high' and len(opts)==4: questions.append(item)
        else: needs.append(item)
    payload={'questions':questions,'needs_review':needs,'stats':{'parsed':len(questions),'needs_review':len(needs),'key_items':len(key)}}
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(payload,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(payload['stats'],ensure_ascii=False))
if __name__=='__main__': main()
