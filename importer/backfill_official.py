#!/usr/bin/env python3
"""Backfill de provas oficiais do Revalida para o Revalida OS.

Objetivo inicial: importar 2026/1, 2025/2 e 2025/1 com caderno oficial +
gabarito oficial, sem inventar questões nem respostas.

Fail-closed:
- só mescla uma edição se detectar exatamente 100 questões objetivas;
- cada questão precisa ter A/B/C/D com extração de alta confiança;
- o gabarito deve cobrir pelo menos 95 questões;
- se falhar, gera relatório em importer/staging e mantém o pack publicado.

O script descobre links nas páginas do INEP e, como fallback, testa padrões de
nomes usados pelo próprio download.inep.gov.br. Para 2025/2, prefere Caderno 1
(e gabarito do mesmo caderno), pois a edição foi publicada em cadernos.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup

from import_revalida import pdf_text, parse_key, parse_questions

UA = {"User-Agent": "RevalidaOS-official-backfill/1.2 (+personal study app)"}
DOWNLOAD_BASE = "https://download.inep.gov.br/revalida/provas_e_gabaritos/"
MAIN_PAGE = "https://www.gov.br/inep/pt-br/areas-de-atuacao/avaliacao-e-exames-educacionais/revalida/provas-e-gabaritos"
SOURCE_PAGES = [
    MAIN_PAGE,
    "https://www.gov.br/inep/pt-br/centrais-de-conteudo/noticias/revalida",
    "https://www.gov.br/inep/pt-br/acesso-a-informacao/perguntas-frequentes/exame-nacional-de-revalidacao-de-diplomas-medicos-expedidos-por-instituicoes-de-educacao-superior-estrangeira-revalida",
]

# Fontes oficiais confirmadas ou padrões oficiais observados. O resolver continua
# validando o conteúdo HTTP antes de aceitar qualquer URL.
KNOWN_SOURCES: dict[tuple[int, int], dict[str, list[str]]] = {
    (2025, 1): {
        "exam": [
            DOWNLOAD_BASE + "2025_1_PV_objetiva_regular.pdf",
        ],
        "key": [
            DOWNLOAD_BASE + "2025_1_GB_objetiva_definitivo.pdf",
        ],
    },
    (2025, 2): {
        "exam": [
            DOWNLOAD_BASE + "2025_2_caderno_1.pdf",
            DOWNLOAD_BASE + "2025_2_caderno_01.pdf",
            DOWNLOAD_BASE + "2025_2_caderno_1_regular.pdf",
            DOWNLOAD_BASE + "2025_2_caderno_1_ampliada.pdf",
        ],
        "key": [
            DOWNLOAD_BASE + "2025_2_gabarito_caderno_1.pdf",
            DOWNLOAD_BASE + "2025_2_gabarito_caderno_1_definitivo.pdf",
            DOWNLOAD_BASE + "2025_2_gabarito_definitivo_caderno_1.pdf",
            DOWNLOAD_BASE + "2025_2_gabarito_caderno_1_preliminar.pdf",
        ],
    },
    (2026, 1): {
        "exam": [
            DOWNLOAD_BASE + "2026_1_caderno_1.pdf",
            DOWNLOAD_BASE + "2026_1_caderno_01.pdf",
            DOWNLOAD_BASE + "2026_1_caderno_1_regular.pdf",
            DOWNLOAD_BASE + "2026_1_caderno_1_ampliada.pdf",
        ],
        "key": [
            DOWNLOAD_BASE + "2026_1_gabarito_caderno_1.pdf",
            DOWNLOAD_BASE + "2026_1_gabarito_caderno_1_definitivo.pdf",
            DOWNLOAD_BASE + "2026_1_gabarito_definitivo_caderno_1.pdf",
            DOWNLOAD_BASE + "2026_1_gabarito_caderno_1_preliminar.pdf",
        ],
    },
}

@dataclass(frozen=True)
class Edition:
    year: int
    half: int

    @property
    def label(self) -> str:
        return f"{self.year}/{self.half}"

    @property
    def token(self) -> str:
        return f"{self.year}_{self.half}"

    @property
    def exam_id(self) -> str:
        return f"revalida-{self.year}-{self.half}"


def parse_editions(raw: str) -> list[Edition]:
    out: list[Edition] = []
    for part in re.split(r"[,;\s]+", raw.strip()):
        if not part:
            continue
        m = re.fullmatch(r"(20\d{2})[/_-]([12])", part)
        if not m:
            raise SystemExit(f"edição inválida: {part!r}; use 2026/1,2025/2,2025/1")
        out.append(Edition(int(m.group(1)), int(m.group(2))))
    return out


def get(session: requests.Session, url: str, *, timeout: int = 45) -> requests.Response:
    r = session.get(url, timeout=timeout, allow_redirects=True)
    r.raise_for_status()
    return r


def is_pdf_response(r: requests.Response) -> bool:
    ctype = (r.headers.get("content-type") or "").lower()
    return "pdf" in ctype or r.content[:4] == b"%PDF"


def _is_inep_pdf(url: str) -> bool:
    low = url.lower()
    return low.startswith("https://download.inep.gov.br/") and "/revalida/" in low


def _is_revalida_gov_page(url: str) -> bool:
    low = url.lower()
    return low.startswith("https://www.gov.br/inep/") and "revalida" in low


def discover_links(session: requests.Session, editions: list[Edition]) -> list[dict]:
    """Descobre PDFs oficiais seguindo páginas do próprio Inep.

    O portal de Provas e Gabaritos usa componentes dinâmicos, por isso a busca
    não depende só da página principal. Também percorre páginas oficiais do
    Revalida e orientações da edição, com profundidade limitada.
    """
    seeds = list(SOURCE_PAGES)
    for ed in editions:
        seeds += [
            f"https://www.gov.br/inep/pt-br/areas-de-atuacao/avaliacao-e-exames-educacionais/revalida/orientacoes/revalida-{ed.year}-{ed.half}",
            f"https://www.gov.br/inep/pt-br/centrais-de-conteudo/legislacao/revalida/{ed.year}",
        ]

    found: dict[str, dict] = {}
    queue: list[tuple[str, int]] = [(u, 0) for u in seeds]
    visited: set[str] = set()
    max_pages = 80

    while queue and len(visited) < max_pages:
        page, depth = queue.pop(0)
        if page in visited:
            continue
        visited.add(page)
        try:
            r = get(session, page, timeout=35)
        except Exception as exc:
            print(f"WARN página indisponível: {page}: {exc}", file=sys.stderr)
            continue

        ctype = (r.headers.get("content-type") or "").lower()
        if is_pdf_response(r):
            if _is_inep_pdf(r.url):
                found[r.url] = {"url": r.url, "label": Path(r.url).name, "source_page": page}
            continue
        if "html" not in ctype and "text" not in ctype:
            continue

        soup = BeautifulSoup(r.text, "html.parser")
        for a in soup.find_all("a", href=True):
            href = urljoin(page, a["href"]).split("#", 1)[0]
            text = " ".join(a.stripped_strings).strip()
            low = f"{href} {text}".lower()

            if _is_inep_pdf(href) or ("download.inep.gov.br" in href.lower() and ".pdf" in href.lower()):
                found[href] = {"url": href, "label": text or Path(href).name, "source_page": page}
                continue

            if depth < 2 and _is_revalida_gov_page(href):
                # Segue apenas páginas plausivelmente relacionadas a prova, gabarito,
                # orientação, notícia ou ano das edições solicitadas.
                years = {str(e.year) for e in editions}
                if any(y in low for y in years) or any(k in low for k in ("prova", "gabarito", "orienta", "noticia", "resultado")):
                    queue.append((href, depth + 1))

    return list(found.values())


def edition_in_text(item: dict, ed: Edition) -> bool:
    s = f"{item.get('label','')} {item.get('url','')}".lower()
    patterns = [
        rf"(?<!\d){ed.year}\s*[/_.-]\s*{ed.half}(?!\d)",
        rf"(?<!\d){ed.year}\s+{ed.half}(?!\d)",
    ]
    return any(re.search(p, s) for p in patterns)


def item_kind(item: dict) -> str | None:
    s = f"{item.get('label','')} {item.get('url','')}".lower()
    if "gabarito" in s or "_gb_" in s:
        return "key"
    if ("prova" in s or "caderno" in s or "_pv_" in s) and "gabarito" not in s:
        if any(x in s for x in ("discurs", "pep", "habilidades", "libras")):
            return None
        return "exam"
    return None


def caderno_no(item: dict) -> int | None:
    s = f"{item.get('label','')} {item.get('url','')}".lower()
    m = re.search(r"caderno[_\s-]*0?([1-9])", s)
    return int(m.group(1)) if m else None


def score(item: dict, *, kind: str, preferred_caderno: int | None = None) -> tuple:
    s = f"{item.get('label','')} {item.get('url','')}".lower()
    cad = caderno_no(item)
    if kind == "key":
        return (
            200 if "definit" in s or "final" in s else 0,
            50 if preferred_caderno and cad == preferred_caderno else 0,
            20 if cad == 1 else 0,
            10 if "objetiva" in s else 0,
            -len(s),
        )
    return (
        80 if preferred_caderno and cad == preferred_caderno else 0,
        40 if cad == 1 else 0,
        30 if "regular" in s else 0,
        20 if "objetiva" in s or "_pv_" in s else 0,
        -20 if "ampliada" in s else 0,
        -len(s),
    )


def candidate_urls(ed: Edition) -> tuple[list[str], list[str]]:
    t = ed.token
    exams = list(KNOWN_SOURCES.get((ed.year, ed.half), {}).get("exam", []))
    keys = list(KNOWN_SOURCES.get((ed.year, ed.half), {}).get("key", []))

    exam_names = [
        f"{t}_PV_objetiva_regular.pdf",
        f"{t}_PV_objetiva.pdf",
        f"{t}_PV_objetiva_caderno_1.pdf",
        f"{t}_PV_objetiva_caderno_01.pdf",
        f"{t}_prova_objetiva_regular.pdf",
        f"{t}_prova_objetiva.pdf",
        f"{t}_prova_caderno_1.pdf",
        f"{t}_prova_caderno_01.pdf",
        f"{t}_caderno_1_regular.pdf",
        f"{t}_caderno_01_regular.pdf",
        f"{t}_caderno_1.pdf",
        f"{t}_caderno_01.pdf",
        f"{t}_caderno_1_ampliada.pdf",
        f"{t}_caderno_01_ampliada.pdf",
        f"revalida_{t}_caderno_1.pdf",
        f"revalida_{t}_caderno_01.pdf",
    ]
    key_names = [
        f"{t}_GB_objetiva_definitivo.pdf",
        f"{t}_GB_objetiva_final.pdf",
        f"{t}_gabarito_objetiva_definitivo.pdf",
        f"{t}_gabarito_objetiva_final.pdf",
        f"{t}_gabarito_caderno_1.pdf",
        f"{t}_gabarito_caderno_01.pdf",
        f"{t}_gabarito_caderno_1_definitivo.pdf",
        f"{t}_gabarito_caderno_01_definitivo.pdf",
        f"{t}_gabarito_definitivo_caderno_1.pdf",
        f"{t}_gabarito_definitivo_caderno_01.pdf",
        f"{t}_gabarito_caderno_1_final.pdf",
        f"{t}_gabarito_caderno_01_final.pdf",
        f"{t}_gabarito_caderno_1_preliminar.pdf",
        f"{t}_gabarito_caderno_01_preliminar.pdf",
    ]

    def dedupe(seq: list[str]) -> list[str]:
        return list(dict.fromkeys(seq))

    return dedupe(exams + [DOWNLOAD_BASE + n for n in exam_names]), dedupe(keys + [DOWNLOAD_BASE + n for n in key_names])


def probe_pdf(session: requests.Session, urls: list[str], *, label: str) -> str | None:
    for idx, url in enumerate(urls, 1):
        try:
            print(f"  testando {label} {idx}/{len(urls)}: {Path(url).name}")
            r = session.get(url, timeout=12, allow_redirects=True)
            if r.status_code == 200 and is_pdf_response(r) and _is_inep_pdf(r.url):
                print(f"  fonte oficial encontrada: {r.url}")
                return r.url
        except Exception as exc:
            print(f"  WARN probe {Path(url).name}: {type(exc).__name__}", file=sys.stderr)
    return None


def resolve_sources(session: requests.Session, links: list[dict], ed: Edition) -> tuple[str | None, str | None]:
    # 1) Primeiro testa fontes oficiais conhecidas/padrões de filename. Isso evita
    # depender do HTML dinâmico do portal do Inep.
    guessed_exams, guessed_keys = candidate_urls(ed)
    exam_url = probe_pdf(session, guessed_exams, label="caderno")
    key_url = probe_pdf(session, guessed_keys, label="gabarito")

    # 2) Se algum lado ainda faltar, usa links descobertos por crawling oficial.
    same = [i for i in links if edition_in_text(i, ed)]
    exams = [i for i in same if item_kind(i) == "exam"]
    keys = [i for i in same if item_kind(i) == "key"]

    def valid(url: str | None) -> str | None:
        if not url:
            return None
        try:
            r = session.get(url, timeout=30, allow_redirects=True)
            return r.url if r.status_code == 200 and is_pdf_response(r) and _is_inep_pdf(r.url) else None
        except Exception:
            return None

    if not exam_url and exams:
        exam_item = max(exams, key=lambda i: score(i, kind="exam"), default=None)
        exam_url = valid(exam_item["url"] if exam_item else None)
    preferred_cad = 1
    if exam_url:
        preferred_cad = caderno_no({"url": exam_url, "label": ""}) or 1
    if not key_url and keys:
        key_item = max(keys, key=lambda i: score(i, kind="key", preferred_caderno=preferred_cad), default=None)
        key_url = valid(key_item["url"] if key_item else None)

    # 3) Último recurso: crawling oficial específico desta edição. Fazemos isso
    # apenas quando os nomes conhecidos não resolveram, para o workflow não
    # gastar minutos varrendo o portal antes de testar URLs diretas.
    if not exam_url or not key_url:
        discovered = discover_links(session, [ed])
        same2 = [i for i in discovered if edition_in_text(i, ed)]
        exams2 = [i for i in same2 if item_kind(i) == "exam"]
        keys2 = [i for i in same2 if item_kind(i) == "key"]
        if not exam_url and exams2:
            item = max(exams2, key=lambda i: score(i, kind="exam"), default=None)
            exam_url = valid(item["url"] if item else None)
        if not key_url and keys2:
            item = max(keys2, key=lambda i: score(i, kind="key", preferred_caderno=preferred_cad), default=None)
            key_url = valid(item["url"] if item else None)

    return exam_url, key_url

def download_pdf(session: requests.Session, url: str, path: Path) -> None:
    r = get(session, url, timeout=90)
    if not is_pdf_response(r):
        raise RuntimeError(f"URL não retornou PDF: {url}")
    path.write_bytes(r.content)


def cutoff_for(ed: Edition) -> int | None:
    # Cortes comparáveis ao formato exclusivamente objetivo.
    known = {(2026, 1): 59, (2025, 2): 61}
    return known.get((ed.year, ed.half))


def import_one(session: requests.Session, pack: dict, links: list[dict], ed: Edition, staging: Path) -> tuple[dict, bool]:
    print(f"\n=== {ed.label} ===")
    exam_url, key_url = resolve_sources(session, links, ed)
    report = {
        "edition": ed.label,
        "exam_url": exam_url,
        "key_url": key_url,
        "parsed_total": 0,
        "high_confidence": 0,
        "key_items": 0,
        "published": False,
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }
    report_path = staging / f"{ed.exam_id}-backfill-report.json"

    if not exam_url or not key_url:
        report["error"] = "não foi possível resolver caderno + gabarito oficiais"
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"FALHOU: {report['error']}")
        return pack, False

    with tempfile.TemporaryDirectory() as td:
        ep = Path(td) / "exam.pdf"
        kp = Path(td) / "key.pdf"
        download_pdf(session, exam_url, ep)
        download_pdf(session, key_url, kp)
        exam_text = pdf_text(ep)
        key_text = pdf_text(kp)
        parsed = parse_questions(exam_text)
        key = parse_key(key_text)

    report["parsed_total"] = len(parsed)
    report["high_confidence"] = sum(1 for _, _, opts, conf in parsed if conf == "high" and len(opts) == 4)
    report["key_items"] = len(key)

    structural_ok = (
        len(parsed) == 100
        and report["high_confidence"] == 100
        and len(key) >= 95
        and {n for n, *_ in parsed} == set(range(1, 101))
    )
    if not structural_ok:
        report["error"] = "validação estrutural falhou; pack publicado foi preservado"
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"FALHOU: {report['error']} | parsed={len(parsed)} high={report['high_confidence']} key={len(key)}")
        return pack, False

    key_header = key_text[:5000].lower()
    key_is_final = (
        any(x in key_url.lower() for x in ("definit", "final"))
        or "gabarito definitivo" in key_header
        or "gabarito final" in key_header
    )
    questions = []
    for n, stem, opts, _ in parsed:
        ans = key.get(n)
        questions.append({
            "id": f"{ed.exam_id}-q{n:03d}",
            "examId": ed.exam_id,
            "number": n,
            "source": "INEP",
            "year": ed.year,
            "edition": ed.label,
            "type": "objective",
            "area": "Não classificada",
            "specialty": None,
            "topic": None,
            "stem": stem,
            "options": [
                {"id": f"{ed.exam_id}-q{n:03d}-{label}", "label": label, "text": text}
                for label, text in opts
            ],
            "correctOption": None if ans == "ANULADA" else ans,
            "explanation": None,
            "optionExplanations": None,
            "keyPoint": None,
            "status": "annulled" if ans == "ANULADA" else ("final" if key_is_final and ans else ("preliminary" if ans else "awaiting_key")),
            "officialSourceURL": exam_url,
        })

    # 2025/1 ainda tinha P1 objetiva + P2 discursiva; o corte global não deve ser
    # comparado como se fosse corte da objetiva. Por isso fica None no simulado P1.
    if ed.year == 2025 and ed.half == 1:
        format_version = "objective100_discursive5"
        discursive_count = 5
        objective_duration = 300
    else:
        format_version = "objective100"
        discursive_count = 0
        objective_duration = 300

    exam_meta = {
        "id": ed.exam_id,
        "name": f"Revalida {ed.label}",
        "year": ed.year,
        "edition": ed.label,
        "board": "INEP",
        "formatVersion": format_version,
        "objectiveQuestions": 100,
        "discursiveQuestions": discursive_count,
        "durationMinutes": objective_duration,
        "officialCutoff": cutoff_for(ed),
        "examDate": None,
        "sourceURL": exam_url,
    }

    exams = {e["id"]: e for e in pack.get("exams", [])}
    exams[ed.exam_id] = exam_meta
    pack["exams"] = list(exams.values())

    qmap = {q["id"]: q for q in pack.get("questions", [])}
    for q in questions:
        qmap[q["id"]] = q
    pack["questions"] = list(qmap.values())

    report["published"] = True
    report["key_status"] = "final" if key_is_final else "preliminary"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"OK: 100 questões importadas; gabarito {report['key_status']}")
    return pack, True


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", type=Path, default=Path("content/packs/latest.json"))
    ap.add_argument("--editions", default="2026/1,2025/2,2025/1")
    ap.add_argument("--staging-dir", type=Path, default=Path("importer/staging"))
    ap.add_argument("--remove-demo", action="store_true")
    args = ap.parse_args()

    editions = parse_editions(args.editions)
    pack = json.loads(args.pack.read_text(encoding="utf-8"))
    args.staging_dir.mkdir(parents=True, exist_ok=True)

    session = requests.Session()
    session.headers.update(UA)
    links: list[dict] = []
    print("Resolver v1.2: URLs oficiais conhecidas/padrões primeiro; crawling só em fallback")

    successful = 0
    for ed in editions:
        # pula se a edição já tiver as 100 questões INEP completas
        existing = [q for q in pack.get("questions", []) if q.get("examId") == ed.exam_id and q.get("source") == "INEP" and q.get("type") == "objective"]
        if len(existing) >= 100:
            print(f"\n=== {ed.label} ===\nJÁ COMPLETA: {len(existing)} questões; pulando")
            continue
        pack, ok = import_one(session, pack, links, ed, args.staging_dir)
        successful += int(ok)

    if successful:
        if args.remove_demo:
            before = len(pack.get("questions", []))
            pack["questions"] = [q for q in pack.get("questions", []) if q.get("source") != "DEMO" and q.get("status") != "demo"]
            print(f"DEMO removido: {before - len(pack['questions'])} itens")
        pack["version"] = int(pack.get("version", 0)) + 1
        pack["generatedAt"] = datetime.now(timezone.utc).isoformat()
        args.pack.write_text(json.dumps(pack, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"\nPACK ATUALIZADO: v{pack['version']} | {len(pack.get('questions', []))} questões")
    else:
        print("\nNenhuma nova edição foi publicada no pack; veja importer/staging/*.json")


if __name__ == "__main__":
    main()
