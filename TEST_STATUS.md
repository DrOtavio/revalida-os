# Status de validação — Revalida OS V1

## Validado neste ambiente

- Todos os arquivos Swift passam no parser do compilador Swift.
- `Models`, `AppConfig`, `SQLiteStore` e `AppRepository` passam em `swiftc -typecheck` com SQLite3.
- Todos os scripts Python passam em `py_compile`.
- O pack inicial passa em `validate_pack.py`.
- JSONs e YAMLs dos workflows são válidos.
- AppIcon: PNG RGB 1024×1024.
- Manifesto do feed usa SHA-256 do pack.

## Limite do ambiente atual

Este ambiente é Linux e não possui Xcode nem o SDK de iOS. Por isso, o binário `.ipa` não pode ser compilado localmente aqui.

O repositório inclui `.github/workflows/build-ipa.yml`, que executa o build em runner macOS do GitHub, gera o `.app` para `iphoneos` sem assinatura e empacota `RevalidaOS-unsigned.ipa` para posterior assinatura/instalação pelo Impactor.

## Conteúdo do banco

O seed contém 25 itens DEMO para teste funcional. Eles são marcados como DEMO e não são apresentados como questões oficiais. O pipeline oficial fica separado e é fail-closed: uma nova edição não entra como prova completa se a extração estrutural/gabarito não passar nas validações definidas.
