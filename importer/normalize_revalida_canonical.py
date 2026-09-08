#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import tempfile
from collections import Counter
from pathlib import Path

try:
    import pymupdf
except Exception:
    pymupdf = None

from pypdf import PdfReader
from canonical_format import CanonicalQuestion, write_questions

Q_RE = re.compile(r'(?im)^\s*(?:QUEST[ÃA]O|QUESTÃO)\s*(\d{1,3})\s*[\.\-–—:]?\s*')

NOISE_PATTERNS = [
    re.compile(p, re.I) for p in [
        r'^\s*REVALIDA\s*$', r'^\s*INEP\s*$', r'^\s*MINIST[ÉE]RIO DA EDUCA[ÇC][ÃA]O\s*$',
        r'^\s*GOVERNO FEDERAL.*$', r'^\s*UNI[ÃA]O E RECONSTRU[ÇC][ÃA]O\s*$',
        r'^\s*PROVA OBJETIVA\s*$', r'^\s*EDI[ÇC][ÃA]O\s*20\d{2}/[12]\s*$',
        r'^\s*Exame Nacional de Revalida[çc][ãa]o.*$', r'^\s*de Diplomas M[eé]dicos.*$',
        r'^\s*Superior Estrangeira\s*$', r'^\s*\d+\s*$',
    ]
]

ENCLOSED = {
    'Ⓐ':'A','Ⓑ':'B','Ⓒ':'C','Ⓓ':'D',
    'ⓐ':'A','ⓑ':'B','ⓒ':'C','ⓓ':'D',
    '🅐':'A','🅑':'B','🅒':'C','🅓':'D',
}


def extract_candidates(path: Path):
    out = []
    exe = shutil.which('pdftotext')
    if exe:
        for layout in (True, False):
            try:
                with tempfile.TemporaryDirectory() as td:
                    dest = Path(td) / 'out.txt'
                    cmd = [exe]
                    if layout:
                        cmd.append('-layout')
                    cmd += ['-enc','UTF-8',str(path),str(dest)]
                    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=180)
                    text = dest.read_text(encoding='utf-8', errors='replace')
                    if text.strip(): out.append(('pdftotext-layout' if layout else 'pdftotext', text))
            except Exception as exc:
                print('WARN pdftotext', exc)
    if pymupdf is not None:
        try:
            doc = pymupdf.open(str(path))
            for sort in (True, False):
                text = '\n'.join(page.get_text('text', sort=sort) or '' for page in doc)
                if text.strip(): out.append((f'pymupdf-sort-{sort}', text))
        except Exception as exc:
            print('WARN pymupdf', exc)
    try:
        text = '\n'.join((p.extract_text() or '') for p in PdfReader(str(path)).pages)
        if text.strip(): out.append(('pypdf', text))
    except Exception as exc:
        print('WARN pypdf', exc)
    return out


def normalize_line(line: str) -> str:
    for src, dst in ENCLOSED.items():
        line = line.replace(src, dst)
    line = line.replace('\u00ad','').replace('\u00a0',' ')
    line = re.sub(r'[ \t]+', ' ', line).strip()
    return line


def clean_chunk(chunk: str, repeated_lines: set[str]) -> str:
    lines = []
    for raw in chunk.splitlines():
        line = normalize_line(raw)
        if not line:
            lines.append('')
            continue
        if line in repeated_lines:
            continue
        if any(p.match(line) for p in NOISE_PATTERNS):
            continue
        lines.append(line)
    # collapse >2 blank lines
    out=[]; blanks=0
    for line in lines:
        if not line:
            blanks += 1
            if blanks <= 1: out.append('')
        else:
            blanks=0; out.append(line)
    return '\n'.join(out).strip()


def option_marker(line: str):
    s = line.strip()
    for src, dst in ENCLOSED.items():
        s = s.replace(src, dst)
    # remove bullets / ornaments before the letter
    s = re.sub(r'^[•◦▪■□◆◇●○►▶▸›»·*+\-–—\s]+', '', s)
    patterns = [
        r'^\(?\s*([A-D])\s*\)?\s*[\.\-–—:]\s*(.*)$',
        r'^\[\s*([A-D])\s*\]\s*(.*)$',
        r'^([A-D])\s{1,}(.*)$',
        r'^([A-D])\s*$',
    ]
    for p in patterns:
        m = re.match(p, s)
        if m:
            label=m.group(1); rest=m.group(2) if m.lastindex and m.lastindex >= 2 else ''
            return label, rest.strip()
    return None


def split_options(chunk: str):
    lines = chunk.splitlines()
    markers=[]
    for idx,line in enumerate(lines):
        om=option_marker(line)
        if om:
            markers.append((idx,om[0],om[1]))
    # choose first plausible sequential A B C D quartet
    for ai,(aidx,alabel,arest) in enumerate(markers):
        if alabel!='A': continue
        seq=[(aidx,'A',arest)]
        pos=ai+1
        for expected in 'BCD':
            while pos < len(markers) and markers[pos][1] != expected:
                pos += 1
            if pos >= len(markers):
                seq=[]; break
            seq.append(markers[pos]); pos += 1
        if len(seq)!=4: continue
        stem='\n'.join(lines[:seq[0][0]]).strip()
        opts={}
        for j,(idx,label,rest) in enumerate(seq):
            end=seq[j+1][0] if j<3 else len(lines)
            body=[]
            if rest: body.append(rest)
            body.extend(lines[idx+1:end])
            text=' '.join(x.strip() for x in body if x.strip())
            text=re.sub(r'\s+',' ',text).strip()
            opts[label]=text
        if len(stem)>=10 and all(opts.get(x) for x in 'ABCD'):
            return stem, opts, 'OK'
    return chunk.strip(), {x:'' for x in 'ABCD'}, 'REVIEW_REQUIRED'


def score_candidate(text: str):
    matches=list(Q_RE.finditer(text)); nums=[int(m.group(1)) for m in matches]
    exact = nums == list(range(1,101))
    return (1 if exact else 0, len(set(nums) & set(range(1,101))), len(matches), len(text))


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--exam', type=Path, required=True)
    ap.add_argument('--edition', required=True)
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--report', type=Path, required=True)
    args=ap.parse_args()
    y,h=args.edition.split('/')
    exam_id=f'revalida-{y}-{h}'

    candidates=extract_candidates(args.exam)
    if not candidates: raise SystemExit('Nenhum extrator conseguiu ler o PDF')
    ranked=sorted(((score_candidate(t),n,t) for n,t in candidates), reverse=True)
    for score,name,_ in ranked: print('candidate',name,'score',score)
    score,engine,text=ranked[0]
    print('selected',engine,score)

    # repeated short lines are likely headers/footers/watermarks
    freq=Counter(normalize_line(x) for x in text.splitlines() if 2 <= len(normalize_line(x)) <= 90)
    repeated={line for line,count in freq.items() if count >= 8}

    matches=list(Q_RE.finditer(text))
    questions=[]
    for i,m in enumerate(matches):
        n=int(m.group(1))
        if not (1 <= n <= 100): continue
        end=matches[i+1].start() if i+1 < len(matches) else len(text)
        chunk=clean_chunk(text[m.end():end], repeated)
        stem,opts,status=split_options(chunk)
        questions.append(CanonicalQuestion(number=n,text=stem,options=opts,images=[],parse_status=status))

    # deduplicate by number, prefer OK
    qmap={}
    for q in questions:
        old=qmap.get(q.number)
        if old is None or (old.parse_status!='OK' and q.parse_status=='OK'):
            qmap[q.number]=q
    questions=[qmap[n] for n in sorted(qmap)]
    meta={
        'EXAM_ID':exam_id,'EXAM':'REVALIDA','BOARD':'INEP','YEAR':y,'EDITION':args.edition,
        'TYPE':'OBJECTIVE','QUESTION_COUNT':'100','TIME_MINUTES':'300'
    }
    write_questions(args.output,meta,questions)
    ok=sum(q.parse_status=='OK' for q in questions)
    missing=[n for n in range(1,101) if n not in qmap]
    report={
        'edition':args.edition,'extractor':engine,'questions_found':len(questions),'questions_ok':ok,
        'review_required':len(questions)-ok,'missing_numbers':missing,'source_file':str(args.exam)
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False))

if __name__=='__main__': main()
