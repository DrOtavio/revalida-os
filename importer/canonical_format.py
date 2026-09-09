from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

QUESTION_START = re.compile(r'^=== QUESTION (\d{3}) ===$')

@dataclass
class CanonicalQuestion:
    number: int
    text: str
    options: dict[str, str]
    images: list[str]
    parse_status: str = 'OK'


def read_questions(path: Path) -> tuple[dict[str, str], list[CanonicalQuestion]]:
    lines = path.read_text(encoding='utf-8').splitlines()
    meta: dict[str, str] = {}
    questions: list[CanonicalQuestion] = []
    i = 0
    while i < len(lines) and not QUESTION_START.match(lines[i]):
        line = lines[i].strip()
        if line and ':' in line:
            k, v = line.split(':', 1)
            meta[k.strip()] = v.strip()
        i += 1

    while i < len(lines):
        m = QUESTION_START.match(lines[i])
        if not m:
            i += 1
            continue
        number = int(m.group(1))
        i += 1
        fields: dict[str, list[str]] = {}
        current = None
        while i < len(lines) and lines[i] != '=== END QUESTION ===':
            line = lines[i]
            if re.fullmatch(r'[A-Z_]+:', line.strip()):
                current = line.strip()[:-1]
                fields.setdefault(current, [])
            elif current is not None:
                fields[current].append(line)
            i += 1
        if i >= len(lines):
            raise ValueError(f'Questão {number:03d} sem END QUESTION')
        i += 1

        def field(name: str) -> str:
            return '\n'.join(fields.get(name, [])).strip()

        options = {label: field(f'OPTION_{label}') for label in 'ABCDE' if field(f'OPTION_{label}')}
        images_raw = field('IMAGE')
        images = [] if not images_raw or images_raw.upper() == 'NONE' else [x.strip() for x in images_raw.splitlines() if x.strip()]
        questions.append(CanonicalQuestion(
            number=number,
            text=field('TEXT'),
            options=options,
            images=images,
            parse_status=field('PARSE_STATUS') or 'OK',
        ))
    return meta, questions


def read_answer_key(path: Path) -> tuple[dict[str, str], dict[int, str]]:
    meta: dict[str, str] = {}
    answers: dict[int, str] = {}
    for raw in path.read_text(encoding='utf-8').splitlines():
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        m = re.fullmatch(r'Q(\d{3})=(A|B|C|D|E|ANNULLED)', line, re.I)
        if m:
            answers[int(m.group(1))] = m.group(2).upper()
            continue
        if ':' in line:
            k, v = line.split(':', 1)
            meta[k.strip()] = v.strip()
    return meta, answers


def write_questions(path: Path, meta: dict[str, str], questions: list[CanonicalQuestion]) -> None:
    out: list[str] = []
    for k in ['EXAM_ID','EXAM','BOARD','YEAR','EDITION','TYPE','QUESTION_COUNT','TIME_MINUTES']:
        if k in meta:
            out.append(f'{k}: {meta[k]}')
    out.append('')
    for q in questions:
        out += [
            f'=== QUESTION {q.number:03d} ===',
            'PARSE_STATUS:', q.parse_status,
            'TEXT:', q.text.strip(),
            '',
        ]
        labels = [x for x in 'ABCDE' if x in q.options]
        for label in labels:
            out += [f'OPTION_{label}:', q.options.get(label, '').strip(), '']
        out += ['IMAGE:']
        if q.images:
            out.extend(q.images)
        else:
            out.append('NONE')
        out += ['', '=== END QUESTION ===', '']
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('\n'.join(out).rstrip() + '\n', encoding='utf-8')
