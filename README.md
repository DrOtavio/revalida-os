# Revalida OS — V1

Aplicativo iOS local-first para preparação do Revalida: questões, simulados, revisão, analytics, calendário/notícias e atualização remota do banco.

## O que já está implementado

- **Início**: meta diária, acerto geral, questões únicas, revisões, sequência de estudo, último simulado e contagem regressiva.
- **Questões**: filtro por área, resolução sem spoiler, correção, explicação da correta e das incorretas, ponto-chave e fila de revisão.
- **Discursivas**: campo de resposta livre e revelação posterior da resposta oficial/padrão quando disponível.
- **Simulados**:
  - prova oficial por edição quando o pack contém as questões;
  - 100 questões aleatórias balanceadas quando há banco classificado suficiente;
  - mini simulados de 10/20;
  - cronômetro de **5 horas** para 100 questões;
  - mapa da prova, questões marcadas, respostas pendentes e resultado somente ao final;
  - nota, corte/referência, margem e tempo.
- **Revisão**: erros/dúvidas/chutes entram em revisão programada.
- **Desempenho**: acerto por área e curva de simulados.
- **Central Revalida**: sino com badge, notícias/prazos, fontes oficiais e alertas locais.
- **Atualização do banco**: manifesto HTTPS + pack JSON versionado + SHA-256.
- **SQLite local**: histórico e progresso ficam no aparelho.
- **GitHub Actions**:
  - build de `.ipa` sem assinatura;
  - publicação do feed de conteúdo via GitHub Pages;
  - watcher periódico do INEP;
  - auto-ingestão fail-closed de nova prova objetiva quando a estrutura puder ser validada.

## Importante sobre o banco incluído

O pacote inicial contém **25 itens DEMO** somente para testar a interface e o fluxo de estudo. Eles aparecem claramente marcados como `DEMO` e **não são questões oficiais do Revalida**.

Os metadados atuais de Revalida 2026/1 e 2026/2 e os eventos da Central Revalida são usados para demonstrar o funcionamento do sistema. O banco oficial completo deve ser alimentado pelos packs produzidos pelo pipeline de importação/revisão.

O app não inventa gabarito. Estados como `preliminary`, `final`, `annulled` e `awaiting_key` são separados.

---

# Build do IPA sem Mac

A forma mais simples é usar **GitHub Actions**.

1. Crie um repositório no GitHub, por exemplo `revalida-os`.
2. Envie todo o conteúdo desta pasta para a branch `main`.
3. Vá em **Actions → Build unsigned IPA → Run workflow**.
4. Ao terminar, abra o job e baixe o artifact **RevalidaOS-unsigned-ipa**.
5. Dentro dele estará `RevalidaOS-unsigned.ipa`.
6. Use o Impactor/Plume Impactor para assinar e instalar no iPhone/iPad.

O workflow está em `.github/workflows/build-ipa.yml` e usa um runner macOS do próprio GitHub para compilar o target de aparelho (`iphoneos`).

## Ativar atualização remota do banco

1. No GitHub, abra **Settings → Pages**.
2. Configure a fonte como **GitHub Actions**.
3. Execute **Actions → Publish content to GitHub Pages**.
4. Seu manifesto ficará em algo como:

   `https://SEU_USUARIO.github.io/revalida-os/manifest.json`

5. No app: **Início → engrenagem → Atualização do banco**.
6. Cole a URL do `manifest.json` e toque em **Verificar atualização**.

A partir daí, atualizar conteúdo não exige gerar um novo IPA.

---

# Como funciona a atualização automática do Revalida

O workflow `watch-inep.yml` roda a cada 6 horas e:

1. consulta páginas oficiais do INEP;
2. detecta novos cadernos, gabaritos, editais e documentos relevantes;
3. sincroniza manchetes recentes da página oficial do Revalida para a Central;
4. tenta parear caderno + gabarito de uma nova edição;
5. extrai a prova comparando PyMuPDF, Poppler (`pdftotext`) e pypdf e usa a extração estruturalmente mais consistente;
6. **só publica automaticamente se validar 100 questões, quatro alternativas por questão e cobertura suficiente do gabarito**;
7. caso contrário, gera relatório em `importer/staging/` e preserva o banco publicado;
8. quando um pack novo é publicado, a versão aumenta e o app o baixa.

Notícias são importadas como notícias. Prazos para alertas locais só recebem `eventDate`/`endDate` quando existe data estruturada e revisada; o watcher não inventa deadline a partir de texto ambíguo.

Questões dependentes de imagem/tabela precisam de revisão de mídia antes de serem consideradas enriquecidas. O objetivo é evitar banco corrompido ou gabarito falso.

---

# Pipeline manual para uma prova

```bash
pip install -r importer/requirements.txt
python importer/import_revalida.py \
  --exam prova.pdf \
  --key gabarito.pdf \
  --exam-id revalida-2026-2 \
  --year 2026 \
  --edition 2026/2 \
  --output importer/staging/revalida-2026-2.json
```

Depois de revisar o staging:

```bash
python importer/build_pack.py \
  --base content/packs/latest.json \
  --staged importer/staging/revalida-2026-2.json \
  --version 2 \
  --output content/packs/latest.json

python importer/validate_pack.py content/packs/latest.json
python importer/make_manifest.py \
  --pack content/packs/latest.json \
  --manifest content/manifest.json \
  --relative-pack packs/latest.json
```

---

# Estrutura técnica

```text
RevalidaOS/
  App/
  Core/
  Database/
  Services/
  Views/
  Resources/
content/
  manifest.json
  packs/latest.json
importer/
  discover_inep.py
  auto_ingest_inep.py
  sync_official_news.py
  import_revalida.py
  validate_pack.py
.github/workflows/
  build-ipa.yml
  publish-content.yml
  watch-inep.yml
project.yml
```

## Stack

- Swift (language mode 5, compilado com Xcode 16+)
- SwiftUI
- SQLite3
- Swift Charts
- UserNotifications
- CryptoKit (SHA-256 dos packs)
- XcodeGen
- GitHub Actions
- GitHub Pages

## Próximos módulos previstos

- Banco oficial histórico completo e classificado por área/tema.
- Comentários clínicos enriquecidos das questões oficiais.
- Imagens/ECG/RX vinculados aos itens.
- Simulado aleatório calibrado pela matriz das últimas edições.
- Estações práticas/PEP.
- ENARE/ENAMED e residências.
