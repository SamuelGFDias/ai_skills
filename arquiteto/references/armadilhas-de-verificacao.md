# Armadilhas de verificação

Complemento da regra 8 do `SKILL.md`. Cada item: sintoma, causa, correção. Vale tanto para o arquiteto verificando quanto para o prompt de um executor que monta script de gate.

## `pkill -f <padrão>` mata o próprio script

- **Sintoma:** o script morre com exit 144 sem executar nada além da primeira linha e sem saída; nada aponta para a causa.
- **Causa:** `pkill -f` casa contra a linha de comando *completa* de todos os processos, e o próprio script (ou o shell que o executa) contém o padrão em alguma linha.
- **Correção:** encerrar por PID capturado no start (arquivo de pid) ou pela porta (`ss -lptn "sport = :PORT"` → `kill`). Se `pkill -f` for inevitável, restringir o padrão ao executável ou excluir o próprio processo (`-v $$`).
- **Princípio:** seletor por padrão de linha de comando inclui o executor; operação destrutiva selecionada por texto precisa excluí-lo explicitamente.

## `dotnet run` ignora variáveis de ambiente exportadas

- **Sintoma:** com todas as variáveis do ambiente-alvo exportadas (inclusive a que define o ambiente), a aplicação sobe — mas em Development, na porta do perfil de launch. O teste "passa" validando o caminho de código que deveria ser evitado.
- **Causa:** em `dotnet run`, o `launchSettings.json` tem precedência sobre o ambiente do processo.
- **Correção:** `dotnet run --no-launch-profile` (ou rodar o binário publicado) e **confirmar o ambiente efetivo na evidência** — extrair a linha de ambiente do log de startup — em vez de checar só "a porta respondeu".
- **Princípio:** configuração exportada não é configuração efetiva; a evidência contém o valor *observado* no processo sob teste, não o que se tentou injetar.

## `curl -o /dev/null URL` sai 0 em 404

- **Sintoma:** loop de readiness (`curl -s -o /dev/null --max-time 2 <url> && break`) declara o serviço pronto ao bater numa rota inexistente; os testes seguintes recebem 404 em tudo e quase são lidos como falha da aplicação.
- **Causa:** `curl` só falha em erro de transporte; qualquer resposta HTTP, inclusive 404/500, sai com 0.
- **Correção:** `-f`/`--fail` (exit reflete status >= 400) ou `-w "%{http_code}"` comparado ao esperado. Usar rota de existência conhecida; 404 é "rota errada", nunca "ainda subindo".
- **Princípio:** exit 0 significa "a ferramenta funcionou", não "o resultado é o esperado" — o gate afirma o conteúdo da resposta.

## 401 vs 403 como prova discriminante sem credencial de usuário

- **Sintoma (risco):** o caminho feliz completo (token real → 200) é inalcançável, por exemplo só há token de service account sem cadastro na aplicação, e a conclusão preguiçosa é "não dá para testar".
- **Causa:** 401 é falha de *autenticação* (assinatura, issuer, audience); 403 é falha de *autorização* (identidade aceita, permissão negada).
- **Correção:** obter 403 com o token real contra 401 com token forjado prova que a validação do token passou. Procurar um par de entradas cuja resposta difira **só** na camada corrigida e registrar na evidência por que o status "de erro" é a prova positiva buscada.
- **Princípio:** quando o sucesso completo é inacessível, a evidência forte é o contraste discriminante — falha na etapa seguinte à corrigida prova que a corrigida passou.
