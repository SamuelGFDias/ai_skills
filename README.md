# 🤖 AI Skills

Repositório de **skills, prompts e instruções reutilizáveis para agentes de IA**, organizados por domínio e finalidade.

O objetivo é centralizar conhecimento técnico e procedimentos que podem ser utilizados por ferramentas como **ChatGPT, Codex e outros agentes de desenvolvimento** para executar tarefas de forma mais consistente.

## 📁 Estrutura

Cada diretório representa uma skill específica.

Exemplos:

```text
ai_skills/
├── abrir-issue-gitlab/
├── arquiteto/
├── audit-log/
├── backend-diretriz/
├── dotnet-backend-architecture/
├── gitlab-auto-merge/
├── hangfire-setup/
├── keycloak-api/
├── nexus-nuget/
├── passbolt-cli/
├── replatforms/
├── ses-gitlab-deps/
└── ...
```

As skills podem conter instruções, padrões, exemplos e fluxos de trabalho relacionados a diferentes tarefas de engenharia de software.

## 🧠 O que é uma Skill?

Uma **skill** é um conjunto de instruções especializadas que fornece contexto e regras para um agente de IA executar determinada tarefa.

Por exemplo, uma skill pode ensinar o agente a:

* criar ou analisar uma arquitetura de software;
* abrir issues seguindo um padrão;
* configurar serviços e ferramentas;
* seguir convenções de desenvolvimento;
* analisar logs e auditorias;
* trabalhar com GitLab;
* configurar autenticação com Keycloak;
* utilizar Hangfire;
* aplicar padrões de arquitetura .NET;
* executar procedimentos internos de desenvolvimento.

## 📦 Estrutura recomendada de uma Skill

Cada skill deve possuir seu próprio diretório.

Exemplo:

```text
nome-da-skill/
└── SKILL.md
```

Exemplo de conteúdo:

```markdown
# Nome da Skill

## Objetivo

Descreva o objetivo da skill.

## Quando utilizar

Explique em quais situações o agente deve utilizar esta skill.

## Instruções

Defina as regras e o fluxo que o agente deve seguir.

## Exemplos

Inclua exemplos de entradas, comandos ou resultados esperados.
```

## ✍️ Convenções

Ao criar novas skills:

1. Utilize nomes de diretórios claros e objetivos.
2. Prefira nomes em `kebab-case`.
3. Mantenha cada skill focada em uma responsabilidade.
4. Documente quando a skill deve ser utilizada.
5. Inclua exemplos quando possível.
6. Evite duplicar instruções existentes em outras skills.
7. Atualize a documentação sempre que o processo mudar.

## ➕ Criando uma nova Skill

Crie um novo diretório:

```bash
mkdir minha-nova-skill
```

Crie o arquivo principal:

```bash
touch minha-nova-skill/SKILL.md
```

Depois adicione as alterações ao Git:

```bash
git add .
git commit -m "feat: add minha-nova-skill"
git push
```

## 🔄 Atualizando o repositório

Antes de enviar novas alterações, sincronize sua branch local:

```bash
git pull --rebase origin main
```

Depois:

```bash
git push origin main
```

## 🎯 Objetivo do projeto

Construir uma biblioteca de conhecimento reutilizável que permita que agentes de IA entendam melhor os padrões, tecnologias e processos utilizados nos projetos, reduzindo trabalho repetitivo e aumentando a consistência das respostas e implementações.

---

