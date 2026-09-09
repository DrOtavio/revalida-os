#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, re, shutil
from datetime import datetime, timezone
from pathlib import Path
from canonical_format import read_questions, read_answer_key

def cutoff_for(y, h):
    return {(2026, 1): 59, (2025, 2): 61}.get((y, h))

def normalize_display_text(value: str) -> str:
    value = value.replace("\u00ad", "").replace("\u00a0", " ").strip()
    value = re.sub(r"(?<=\w)-\s*\n\s*(?=\w)", "-", value)
    paragraphs = re.split(r"\n\s*\n+", value)
    cleaned = []
    for paragraph in paragraphs:
        paragraph = re.sub(r"\s*\n\s*", " ", paragraph)
        paragraph = re.sub(r"\s+", " ", paragraph).strip()
        paragraph = re.sub(r"(?<=\w)-\s+(?=\w)", "-", paragraph)
        paragraph = re.sub(r"\s+([,.;:!?])", r"\1", paragraph)
        if paragraph:
            cleaned.append(paragraph)
    return "\n\n".join(cleaned)

def load_metadata(path: Path | None, questions) -> dict[int, dict[str, str]]:
    if path is None or not path.exists():
        return {}
    raw = json.loads(path.read_text(encoding="utf-8"))
    items = raw.get("questions", {})
    result: dict[int, dict[str, str]] = {}
    for q in questions:
        key = f"Q{q.number:03d}"
        item = items.get(key)
        if not isinstance(item, dict):
            raise SystemExit(f"ERRO metadata: {key} ausente")
        for field in ("area", "specialty", "topic"):
            if not str(item.get(field, "")).strip():
                raise SystemExit(f"ERRO metadata: {key}.{field} vazio")
        result[q.number] = {
            "area": str(item["area"]).strip(),
            "specialty": str(item["specialty"]).strip(),
            "topic": str(item["topic"]).strip(),
        }
    print(f"METADATA: {len(result)}/{len(questions)} questões classificadas")
    return result

def load_explanations(path: Path | None, questions, option_labels: list[str]) -> dict[int, dict]:
    if path is None or not path.exists():
        print("EDITORIAL: explanations.json não encontrado; preservando comentários existentes, se houver")
        return {}

    raw = json.loads(path.read_text(encoding="utf-8"))
    items = raw.get("questions")
    if not isinstance(items, dict):
        raise SystemExit("ERRO explanations: campo 'questions' ausente ou inválido")

    result: dict[int, dict] = {}
    for q in questions:
        key = f"Q{q.number:03d}"
        item = items.get(key)
        if not isinstance(item, dict):
            raise SystemExit(f"ERRO explanations: {key} ausente")
        explanation = str(item.get("explanation", "")).strip()
        key_point = str(item.get("keyPoint", "")).strip()
        option_explanations = item.get("optionExplanations")
        if not explanation:
            raise SystemExit(f"ERRO explanations: {key}.explanation vazio")
        if not key_point:
            raise SystemExit(f"ERRO explanations: {key}.keyPoint vazio")
        if not isinstance(option_explanations, dict):
            raise SystemExit(f"ERRO explanations: {key}.optionExplanations inválido")
        missing = [label for label in option_labels if not str(option_explanations.get(label, "")).strip()]
        if missing:
            raise SystemExit(f"ERRO explanations: {key}.optionExplanations faltando {', '.join(missing)}")
        result[q.number] = {
            "explanation": explanation,
            "optionExplanations": {label: str(option_explanations[label]).strip() for label in option_labels},
            "keyPoint": key_point,
        }
    print(f"EDITORIAL: {len(result)}/{len(questions)} questões com comentário completo")
    return result

def load_stem_overrides(path: Path | None) -> dict[int, str]:
    """Optional display-only stems for questions whose PDF tables were flattened into prose."""
    if path is None or not path.exists():
        return {}

    raw = json.loads(path.read_text(encoding="utf-8"))
    items = raw.get("stemOverrides", {})
    if not isinstance(items, dict):
        raise SystemExit("ERRO media: campo 'stemOverrides' deve ser objeto")

    result: dict[int, str] = {}
    for key, value in items.items():
        match = re.fullmatch(r"Q(\d{3})", str(key).strip().upper())
        if not match:
            raise SystemExit(f"ERRO media: stemOverride com chave inválida: {key}")
        text = str(value).strip()
        if not text:
            raise SystemExit(f"ERRO media: stemOverride vazio em {key}")
        result[int(match.group(1))] = text

    if result:
        print(f"TEXTO DE EXIBIÇÃO: {len(result)} questões com tabela sem texto achatado")
    return result

def load_media_manifest(path: Path | None, questions, source_folder: str, source_media_dir: Path) -> dict[int, list[dict]]:
    result: dict[int, list[dict]] = {}
    if path is None or not path.exists():
        return result

    raw = json.loads(path.read_text(encoding="utf-8"))
    items = raw.get("questions")
    if not isinstance(items, dict):
        raise SystemExit("ERRO media: campo 'questions' ausente ou inválido")

    for q in questions:
        key = f"Q{q.number:03d}"
        entries = items.get(key, [])
        if entries in ("", None):
            entries = []
        if not isinstance(entries, list):
            raise SystemExit(f"ERRO media: {key} deve ser lista")
        built = []
        for idx, item in enumerate(entries, start=1):
            if not isinstance(item, dict):
                raise SystemExit(f"ERRO media: {key}[{idx}] inválido")
            kind = str(item.get("kind", "")).strip().lower()
            if kind not in {"image", "table"}:
                raise SystemExit(f"ERRO media: {key}[{idx}] kind inválido")
            media_id = f"{key.lower()}-media-{idx}"
            title = str(item.get("title", "")).strip() or None
            caption = str(item.get("caption", "")).strip() or None
            alt_text = str(item.get("altText", "")).strip() or None

            def public_url_for(file_name: str) -> str:
                return f"media/revalida/{source_folder}/{file_name}"

            if kind == "image":
                file_name = str(item.get("file", "")).strip()
                url = str(item.get("url", "")).strip() or None
                if file_name:
                    if not (source_media_dir / file_name).exists():
                        raise SystemExit(f"ERRO media: arquivo ausente {source_media_dir / file_name}")
                    url = public_url_for(file_name)
                if not url:
                    raise SystemExit(f"ERRO media: {key}[{idx}] image precisa de file ou url")
                built.append({
                    "id": media_id,
                    "kind": "image",
                    "title": title,
                    "caption": caption,
                    "url": url,
                    "table": None,
                    "altText": alt_text,
                })
            else:
                columns = item.get("columns")
                rows = item.get("rows")
                if not isinstance(columns, list) or not columns:
                    raise SystemExit(f"ERRO media: {key}[{idx}] table.columns inválido")
                if not isinstance(rows, list):
                    raise SystemExit(f"ERRO media: {key}[{idx}] table.rows inválido")
                fallback = str(item.get("fallbackImage", "")).strip() or None
                url = None
                if fallback:
                    if not (source_media_dir / fallback).exists():
                        raise SystemExit(f"ERRO media: fallback ausente {source_media_dir / fallback}")
                    url = public_url_for(fallback)
                built.append({
                    "id": media_id,
                    "kind": "table",
                    "title": title,
                    "caption": caption,
                    "url": url,
                    "table": {
                        "columns": [str(c).strip() for c in columns],
                        "rows": [[str(cell).strip() for cell in row] for row in rows],
                    },
                    "altText": alt_text,
                })
        if built:
            result[q.number] = built
    print(f"MÍDIA: {sum(len(v) for v in result.values())} itens em {len(result)} questões")
    return result

def copy_media_assets(source_media_dir: Path, content_media_dir: Path):
    if not source_media_dir.exists():
        print("MÍDIA: sem pasta media/ para copiar")
        return
    content_media_dir.mkdir(parents=True, exist_ok=True)
    count = 0
    for item in source_media_dir.rglob("*"):
        if item.is_file():
            rel = item.relative_to(source_media_dir)
            dest = content_media_dir / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(item, dest)
            count += 1
    print(f"MÍDIA: {count} arquivo(s) copiados para {content_media_dir}")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--questions", type=Path, required=True)
    ap.add_argument("--key", type=Path, required=True)
    ap.add_argument("--metadata", type=Path)
    ap.add_argument("--explanations", type=Path)
    ap.add_argument("--media-manifest", type=Path)
    ap.add_argument("--pack", type=Path, default=Path("content/packs/latest.json"))
    ap.add_argument("--remove-demo", action="store_true")
    args = ap.parse_args()

    meta, qs = read_questions(args.questions)
    _, key = read_answer_key(args.key)

    metadata_path = args.metadata or args.questions.with_name("metadata.json")
    explanations_path = args.explanations or args.questions.with_name("explanations.json")
    media_manifest_path = args.media_manifest or args.questions.with_name("media_manifest.json")

    sample_labels = list(qs[0].options.keys()) if qs else list("ABCD")
    classifications = load_metadata(metadata_path if metadata_path.exists() else None, qs)
    editorial = load_explanations(explanations_path if explanations_path.exists() else None, qs, sample_labels)

    source_folder = args.questions.parent.name
    source_media_dir = args.questions.parent / "media"
    content_root = args.pack.parent.parent
    content_media_dir = content_root / "media" / "revalida" / source_folder
    media_manifest = load_media_manifest(media_manifest_path if media_manifest_path.exists() else None, qs, source_folder, source_media_dir)
    stem_overrides = load_stem_overrides(media_manifest_path if media_manifest_path.exists() else None)
    if media_manifest or source_media_dir.exists():
        copy_media_assets(source_media_dir, content_media_dir)

    y = int(meta["YEAR"])
    label = meta["EDITION"]
    h = int(label.split("/")[1]) if "/" in label else 1
    exam_id = meta["EXAM_ID"]
    key_final = True

    pack = json.loads(args.pack.read_text(encoding="utf-8"))
    exams = {e["id"]: e for e in pack.get("exams", [])}
    exams[exam_id] = {
        "id": exam_id,
        "name": f"Revalida {label}",
        "year": y,
        "edition": label,
        "board": "INEP",
        "formatVersion": "objective100_discursive5" if (y, h) == (2025, 1) else "objective100",
        "objectiveQuestions": int(meta.get("QUESTION_COUNT", "100")),
        "discursiveQuestions": 5 if (y, h) == (2025, 1) else 0,
        "durationMinutes": int(meta.get("TIME_MINUTES", "300")),
        "officialCutoff": cutoff_for(y, h),
        "examDate": None,
        "sourceURL": None,
    }
    pack["exams"] = list(exams.values())

    qmap = {q["id"]: q for q in pack.get("questions", [])}
    for q in qs:
        ans = key[q.number]
        qid = f"{exam_id}-q{q.number:03d}"
        stem_source = stem_overrides.get(q.number, q.text)
        stem = normalize_display_text(stem_source)
        option_labels = list(q.options.keys())
        options = {a: normalize_display_text(q.options[a]) for a in option_labels}
        cls = classifications.get(q.number, {})
        prev = qmap.get(qid, {})
        ed = editorial.get(q.number, {})

        media_items = media_manifest.get(q.number, prev.get("media", []))
        if not media_items and q.images:
            auto = []
            for idx, path in enumerate(q.images, start=1):
                file_name = path.strip().replace("\\", "/").split("/")[-1]
                if file_name and (source_media_dir / file_name).exists():
                    auto.append({
                        "id": f"q{q.number:03d}-img-{idx}",
                        "kind": "image",
                        "title": None,
                        "caption": None,
                        "url": f"media/revalida/{source_folder}/{file_name}",
                        "table": None,
                        "altText": f"Imagem da questão {q.number}",
                    })
            media_items = auto

        qmap[qid] = {
            "id": qid,
            "examId": exam_id,
            "number": q.number,
            "source": "INEP",
            "year": y,
            "edition": label,
            "type": "objective",
            "area": cls.get("area", "Não classificada"),
            "specialty": cls.get("specialty"),
            "topic": cls.get("topic"),
            "stem": stem,
            "options": [{"id": f"{qid}-{a}", "label": a, "text": options[a]} for a in option_labels],
            "correctOption": None if ans == "ANNULLED" else ans,
            "explanation": ed.get("explanation", prev.get("explanation")),
            "optionExplanations": ed.get("optionExplanations", prev.get("optionExplanations")),
            "keyPoint": ed.get("keyPoint", prev.get("keyPoint")),
            "status": "annulled" if ans == "ANNULLED" else ("final" if key_final else "preliminary"),
            "officialSourceURL": prev.get("officialSourceURL"),
            "mediaStatus": "ready" if media_items else "none",
            "media": media_items,
        }

    pack["questions"] = list(qmap.values())
    if args.remove_demo:
        pack["questions"] = [q for q in pack["questions"] if q.get("source") != "DEMO" and q.get("status") != "demo"]

    pack["version"] = int(pack.get("version", 0)) + 1
    pack["generatedAt"] = datetime.now(timezone.utc).isoformat()
    args.pack.write_text(json.dumps(pack, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f'OK canonical import {label}: pack v{pack["version"]}, total={len(pack["questions"])}, editorial={len(editorial)}')

if __name__ == "__main__":
    main()
