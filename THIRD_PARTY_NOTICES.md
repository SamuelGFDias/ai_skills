# Avisos de terceiros

Algumas skills deste repositório foram adaptadas de projetos de terceiros. Cada uma traz no topo a nota de origem.

## Everything Claude Code (ECC)

- Fonte: https://github.com/affaan-m/ECC (pacote npm `ecc-universal` 2.2.3)
- Skills adaptadas: `angular-developer`, `api-design`, `architecture-decision-records`, `codebase-onboarding`, `context-budget`, `csharp-testing`, `database-migrations`, `dotnet-patterns`, `healthcare-phi-compliance`, `security-review`, `verification-loop`.
- Trechos incorporados (sem cópia literal): checklists dos agents `silent-failure-hunter`, `security-reviewer` e `build-error-resolver` nos papéis do `arquiteto`; tabela de tiers do `orch-pipeline` na regra 19 do `arquiteto`; detecção do runner, relatório de evidência RED/GREEN e erros comuns de teste da `tdd-workflow` na `tdd-first`.

Licença original:

```
MIT License

Copyright (c) 2026 Affaan Mustafa

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Cloudflare security-audit-skill

- Fonte: https://github.com/cloudflare/security-audit-skill (commit c1c8a8c)
- Skill incorporada sem alterações além do cabeçalho do repo: `security-audit`.
- Trechos adaptados (sem cópia literal): regra de evidência, âncoras de severidade e anti-padrões na `security-review`.

Licença original:

```
MIT License

Copyright (c) 2025-2026 Cloudflare, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Anthropic skills — frontend-design

- Fonte: https://github.com/anthropics/skills (`skills/frontend-design`, commit e4bb5d9)
- Skill incorporada sem alterações além do frontmatter e do cabeçalho do repo: `frontend-design`.
- Licença: Apache-2.0, texto completo em `frontend-design/LICENSE.txt`.

## UI UX Pro Max

- Fonte: https://github.com/nextlevelbuilder/ui-ux-pro-max-skill (`.claude/skills/ui-ux-pro-max`, commit e59ff37)
- Skill incorporada: `ui-ux-pro-max`. Alterações: frontmatter, cabeçalho do repo, caminho dos scripts e remoção de `scripts/tests`.
- Licença: MIT, Copyright (c) 2024 Next Level Builder, texto completo em `ui-ux-pro-max/LICENSE`.

## taste-skill (tasteskill 2.5.1)

- Fonte: https://github.com/Leonxlnx/taste-skill (`skills/taste-skill`, commit f6b7657)
- Skill incorporada como `design-taste-frontend`, sem alterações além da description em uma linha e do cabeçalho do repo.
- Licença: MIT, Copyright (c) 2026 Leonxlnx, texto completo em `design-taste-frontend/LICENSE`. As fotografias em `assets/photos` têm créditos próprios, listados pelo `scripts/photos.mjs credits`.
