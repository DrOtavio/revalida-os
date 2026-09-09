#!/usr/bin/env python3
from __future__ import annotations
import argparse, json
from pathlib import Path
from canonical_format import read_questions, read_answer_key


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--questions',type=Path,required=True)
    ap.add_argument('--key',type=Path,required=True)
    ap.add_argument('--media-root',type=Path)
    ap.add_argument('--json-report',type=Path)
    args=ap.parse_args()
    meta,qs=read_questions(args.questions)
    kmeta,key=read_answer_key(args.key)
    errors=[]; warnings=[]

    expected_count=int(meta.get('QUESTION_COUNT', len(qs) or 100))
    expected_nums=list(range(1, expected_count+1))
    nums=[q.number for q in qs]
    if nums != expected_nums:
        missing=sorted(set(expected_nums)-set(nums))
        errors.append(f'Numeração inválida: encontrados {len(nums)} itens; faltantes={missing}')

    option_sets=[]
    for q in qs:
        if q.parse_status!='OK': errors.append(f'Q{q.number:03d}: PARSE_STATUS={q.parse_status}')
        if len(q.text.strip())<10: errors.append(f'Q{q.number:03d}: enunciado vazio/curto')
        labels=[x for x in 'ABCDE' if q.options.get(x,'').strip()]
        option_sets.append(''.join(labels))
        if labels[:4] != list('ABCD'):
            errors.append(f'Q{q.number:03d}: alternativas A-D obrigatórias; encontradas={labels}')
        for label in labels:
            if len(q.options.get(label,'').strip())<1:
                errors.append(f'Q{q.number:03d}: OPTION_{label} vazio')
        for image in q.images:
            if args.media_root and not (args.media_root/image).exists():
                errors.append(f'Q{q.number:03d}: imagem ausente {image}')

    if set(key)!=set(expected_nums):
        errors.append(f'Gabarito deve conter Q001-Q{expected_count:03d}; itens={len(key)}')
    qmap={q.number:q for q in qs}
    for n,a in key.items():
        if a == 'ANNULLED': continue
        valid=set(qmap.get(n).options) if n in qmap else set('ABCDE')
        if a not in valid:
            errors.append(f'Q{n:03d}: gabarito {a} não existe entre as alternativas {sorted(valid)}')
    if meta.get('EDITION') != kmeta.get('EDITION'):
        errors.append('EDITION divergente entre questions.txt e answer_key.txt')

    distinct=sorted(set(option_sets))
    if len(distinct)>1:
        warnings.append(f'Quantidade de alternativas varia dentro da prova: {distinct}')

    status='PASS' if not errors else 'FAIL'
    report={
        'status':status,'questions':len(qs),'answers':len(key),'errors':errors,'warnings':warnings,
        'optionSets':distinct,'metadata':meta,'keyMetadata':kmeta
    }
    if args.json_report:
        args.json_report.parent.mkdir(parents=True,exist_ok=True)
        args.json_report.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f'{status}: questions={len(qs)} answers={len(key)} optionSets={distinct} errors={len(errors)}')
    for e in errors[:50]: print('ERROR',e)
    for w in warnings[:20]: print('WARN',w)
    raise SystemExit(0 if status=='PASS' else 2)

if __name__=='__main__': main()
