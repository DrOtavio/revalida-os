#!/usr/bin/env python3
"""Sincroniza manchetes oficiais do Revalida para a Central do app.

Este script importa apenas metadados/notícias (título, resumo, data e URL oficial).
Ele NÃO tenta inferir automaticamente prazos a partir de texto livre; eventos com
notificações usam datas estruturadas adicionadas ao pack por rotina específica/revisão.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup

NEWS_PAGE = "https://www.gov.br/inep/pt-br/centrais-de-conteudo/noticias/revalida"
UA = {"User-Agent": "RevalidaOS-content-watcher/1.0 (+personal study app)"}


def stable_id(url: str) -> str:
    return "inep-news-" + hashlib.sha1(url.encode("utf-8")).hexdigest()[:16]


def clean(text: str) -> str:
    return re.sub(r"\s+", " ", text or "").strip()


def published_date(soup: BeautifulSoup) -> str | None:
    candidates = [
        soup.find("meta", attrs={"property": "article:published_time"}),
        soup.find("meta", attrs={"name": "DC.date.created"}),
        soup.find("meta", attrs={"name": "date"}),
    ]
    for tag in candidates:
        if tag and tag.get("content"):
            raw = tag.get("content", "")
            m = re.search(r"(20\d{2})-(\d{2})-(\d{2})", raw)
            if m:
                return m.group(0)
    # Gov.br costuma exibir data em <span class="documentPublished"> etc.
    text = clean(soup.get_text(" ", strip=True))
    months = {
        "janeiro": 1, "fevereiro": 2, "março": 3, "abril": 4,
        "maio": 5, "junho": 6, "julho": 7, "agosto": 8,
        "setembro": 9, "outubro": 10, "novembro": 11, "dezembro": 12,
    }
    m = re.search(r"(\d{1,2})\s+de\s+([a-zç]+)\s+de\s+(20\d{2})", text, re.I)
    if m and m.group(2).lower() in months:
        return f"{int(m.group(3)):04d}-{months[m.group(2).lower()]:02d}-{int(m.group(1)):02d}"
    return None


def summarize(soup: BeautifulSoup, fallback: str) -> str:
    for selector in ("article p", ".documentDescription", "main p"):
        node = soup.select_one(selector)
        if node:
            text = clean(node.get_text(" ", strip=True))
            if len(text) >= 40:
                return text[:360]
    return fallback[:360]


def classify(title: str) -> tuple[str, str]:
    t = title.lower()
    if "edital" in t:
        return "Edital", "high"
    if "inscri" in t:
        return "Inscrições", "high"
    if "local de prova" in t or "cartão" in t:
        return "Prova", "high"
    if "gabarito" in t:
        return "Gabarito", "high"
    if "resultado" in t:
        return "Resultado", "high"
    if "recurso" in t:
        return "Recurso", "urgent"
    if "2ª etapa" in t or "segunda etapa" in t or "pep" in t:
        return "2ª etapa", "high"
    return "Notícia", "normal"


def discover_articles(session: requests.Session) -> list[tuple[str, str]]:
    r = session.get(NEWS_PAGE, timeout=30)
    r.raise_for_status()
    soup = BeautifulSoup(r.text, "html.parser")
    out: list[tuple[str, str]] = []
    seen: set[str] = set()
    for a in soup.find_all("a", href=True):
        href = urljoin(NEWS_PAGE, a["href"])
        title = clean(" ".join(a.stripped_strings))
        if not title or len(title) < 12:
            continue
        # Links de artigos do portal; evita a própria página agregadora.
        if "/centrais-de-conteudo/noticias/" not in href or href.rstrip("/") == NEWS_PAGE.rstrip("/"):
            continue
        if href in seen:
            continue
        seen.add(href)
        out.append((href, title))
    return out[:30]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", type=Path, required=True)
    ap.add_argument("--max-items", type=int, default=12)
    args = ap.parse_args()

    pack = json.loads(args.pack.read_text(encoding="utf-8"))
    existing = {n.get("id"): n for n in pack.get("news", [])}
    session = requests.Session()
    session.headers.update(UA)
    current_year = datetime.now(timezone.utc).year
    added = 0

    for url, listing_title in discover_articles(session):
        try:
            r = session.get(url, timeout=30)
            r.raise_for_status()
            soup = BeautifulSoup(r.text, "html.parser")
        except requests.RequestException:
            continue

        title_node = soup.find("h1")
        title = clean(title_node.get_text(" ", strip=True)) if title_node else listing_title
        date = published_date(soup)
        if date:
            try:
                if int(date[:4]) < current_year - 1:
                    continue
            except ValueError:
                pass
        else:
            # Sem data verificável: evita inundar o app com arquivo histórico.
            continue

        nid = stable_id(url)
        if nid in existing:
            continue
        category, priority = classify(title)
        item = {
            "id": nid,
            "title": title,
            "body": summarize(soup, "Publicação oficial do Inep sobre o Revalida."),
            "category": category,
            "priority": priority,
            "publishedAt": date,
            "eventDate": None,
            "endDate": None,
            "sourceURL": url,
            "isRead": False,
        }
        existing[nid] = item
        added += 1
        if added >= max(0, args.max_items):
            break

    if added:
        pack["news"] = list(existing.values())
        pack["version"] = int(pack.get("version", 0)) + 1
        pack["generatedAt"] = datetime.now(timezone.utc).isoformat()
        args.pack.write_text(json.dumps(pack, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"added_news": added, "version": pack.get("version")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
