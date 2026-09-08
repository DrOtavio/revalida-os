#!/usr/bin/env python3
"""Descobre arquivos oficiais publicados nas páginas do Revalida.

Não publica conteúdo clínico sozinho. A função deste watcher é detectar novos links
oficiais e registrar hash/data para o pipeline de ingestão.
"""
from __future__ import annotations
import argparse, hashlib, json, re
from datetime import datetime, timezone
from urllib.parse import urljoin
import requests
from bs4 import BeautifulSoup

PAGES = [
    "https://www.gov.br/inep/pt-br/areas-de-atuacao/avaliacao-e-exames-educacionais/revalida/provas-e-gabaritos",
    "https://www.gov.br/inep/pt-br/centrais-de-conteudo/legislacao/revalida/2026",
    "https://www.gov.br/inep/pt-br/centrais-de-conteudo/noticias/revalida",
]

UA = {"User-Agent": "RevalidaOS-content-watcher/1.0 (+personal study app)"}

def relevant(url: str, text: str) -> bool:
    u=(url+" "+text).lower()
    keys=("revalida","gabarito","prova","caderno","edital","resultado","pep")
    fileish=(".pdf" in u or "@@download" in u or "download.inep" in u or "edital" in u)
    return fileish and any(k in u for k in keys)

def main() -> None:
    ap=argparse.ArgumentParser(); ap.add_argument("--output",required=True); args=ap.parse_args()
    found={}
    session=requests.Session(); session.headers.update(UA)
    for page in PAGES:
        r=session.get(page,timeout=30); r.raise_for_status()
        soup=BeautifulSoup(r.text,"html.parser")
        for a in soup.find_all("a",href=True):
            url=urljoin(page,a["href"]); text=" ".join(a.stripped_strings)
            if relevant(url,text):
                found[url]={"url":url,"label":text[:300],"source_page":page}
        # alguns portais deixam URLs em atributos/scripts
        for raw in re.findall(r'https?://[^\"\'<> ]+',r.text):
            raw=raw.replace('&amp;','&')
            if relevant(raw,raw): found.setdefault(raw,{"url":raw,"label":"link detectado no HTML","source_page":page})
    out={"checked_at":datetime.now(timezone.utc).isoformat(),"items":sorted(found.values(),key=lambda x:x["url"])}
    pathlib=__import__('pathlib').Path(args.output); pathlib.parent.mkdir(parents=True,exist_ok=True); pathlib.write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f"{len(found)} links oficiais detectados")
if __name__=='__main__': main()
