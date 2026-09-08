# Pipeline de conteúdo

1. `discover_inep.py` monitora páginas oficiais e registra links novos.
2. Ao sair um caderno/gabarito, baixe os PDFs oficiais e execute `import_revalida.py`.
3. Revise os itens marcados em `needs_review` (principalmente questões com imagens/tabelas).
4. Classifique `area`, `specialty` e `topic` antes da publicação definitiva.
5. `build_pack.py` mescla a nova edição no pack.
6. `make_manifest.py` gera o hash e o manifesto usado pelo app.
7. O GitHub Pages publica `content/`; o app baixa apenas quando `version` aumenta.

## Regra de qualidade

O pipeline nunca deve inventar gabarito. `preliminary`, `final`, `annulled` e `awaiting_key` são estados distintos. Questões com extração incerta ficam em staging até revisão.
