# Build no Windows — caminho mais curto

Você não precisa instalar Xcode no Windows.

1. Descompacte `RevalidaOS-V1.zip`.
2. Crie um repositório GitHub vazio.
3. Faça upload dos arquivos preservando `.github/workflows/`.
4. Abra a aba **Actions**.
5. Rode **Build unsigned IPA**.
6. Baixe o artifact `RevalidaOS-unsigned-ipa`.
7. Extraia `RevalidaOS-unsigned.ipa`.
8. Abra o Impactor/Plume Impactor e instale esse IPA no aparelho.

Para o feed remoto:

1. GitHub **Settings → Pages → GitHub Actions**.
2. Rode **Publish content to GitHub Pages**.
3. Copie a URL final e acrescente `/manifest.json`.
4. No app, abra a engrenagem e cole essa URL em **Atualização do banco**.

O app seguirá funcionando offline. A internet é usada para sincronizar packs e abrir fontes oficiais.
