---
name: lgpd
description: Práticas de desenvolvimento para cumprir a LGPD (Lei 13.709/2018) em sistemas que tratam dado pessoal, com foco em dado sensível de saúde e em órgão público: classificação de dados, base legal, minimização, logs sem dado pessoal, pseudonimização, controle de acesso, trilha de auditoria, retenção e eliminação, direitos do titular e fluxo de incidente com comunicação à ANPD. Use ao modelar, implementar ou revisar funcionalidade que coleta, exibe, exporta, loga ou compartilha dado pessoal ou de saúde.
---

# Skill: lgpd

**Tipo:** internal

## Quando executar

- Ao criar ou alterar tabela, DTO, endpoint, relatório, exportação, log ou integração que envolva dado pessoal (nome, CPF, CNS, endereço, telefone, e-mail) ou dado sensível (saúde, biometria, genética, origem racial, religião, vida sexual).
- Ao revisar um diff que toque esses dados. O `arquiteto` indica esta skill pelo gatilho de segurança (regra 13).
- Ao responder a um incidente de segurança que envolva dado pessoal.

Para os padrões técnicos detalhados de dado de saúde (controle de acesso por linha, auditoria à prova de adulteração, marcação de schema), combine com a `healthcare-phi-compliance`. Para segurança de código em geral, com a `security-review`.

> **Não é parecer jurídico.** Esta skill traduz a lei em práticas de engenharia. Base legal, finalidade e prazos de retenção de cada tratamento são decisão do controlador, com o encarregado (DPO) e o jurídico. Na dúvida sobre enquadramento, o agente pergunta ao usuário; não decide sozinho.

## Conceitos que mudam o código

Artigos conferidos no texto da Lei 13.709/2018 em planalto.gov.br, em 2026-11-07.

| conceito | onde | consequência no código |
|---|---|---|
| dado pessoal | art. 5º, I | qualquer informação que identifique ou torne identificável uma pessoa, inclusive por combinação (data de nascimento + bairro + sexo) |
| dado sensível | art. 5º, II | **dado de saúde é sensível.** Tem bases legais mais restritas (art. 11) e exige proteção reforçada |
| dado anonimizado | art. 5º, III e XI | fora da LGPD **só se** não puder ser reidentificado com meios técnicos razoáveis. Hash de CPF não é anonimização: dá para reidentificar por força bruta |
| pseudonimização | art. 13, §4º | o dado só volta a identificar alguém com uma informação adicional guardada à parte, em ambiente controlado. Continua sendo dado pessoal, mas reduz o risco |
| controlador e operador | art. 5º, VI e VII | o órgão decide (controlador); o sistema e quem o opera tratam em nome dele (operador) |

## Base legal: todo tratamento precisa de uma

O sistema não escolhe a base legal, mas precisa saber qual é para registrar e para limitar o uso.

- **Dado comum** (art. 7º): consentimento, obrigação legal, execução de políticas públicas pela administração (III), tutela da saúde por profissional, serviço de saúde ou autoridade sanitária (VIII), entre outras.
- **Dado sensível** (art. 11): consentimento específico e destacado, ou, sem consentimento, quando indispensável para obrigação legal, políticas públicas (II, b), tutela da saúde (II, f), proteção da vida, estudos por órgão de pesquisa e outras hipóteses do inciso II.
- **Poder público** (art. 23): o tratamento precisa atender à finalidade pública e às competências legais do órgão, com as hipóteses de tratamento informadas publicamente.
- **Proibições específicas de saúde** (art. 11, §§4º e 5º): compartilhar dado de saúde entre controladores para obter vantagem econômica é vedado, salvo as exceções de prestação de serviço de saúde em benefício do titular. Operadora de plano de saúde não pode usar dado de saúde para selecionar risco.

**No código:** quando a funcionalidade introduz um uso novo de dado pessoal (nova finalidade, novo compartilhamento, nova exportação), registre a pergunta "qual é a base legal e a finalidade?" como pendência para o usuário. Não implemente o compartilhamento em silêncio.

## Práticas de engenharia

Os princípios do art. 6º (finalidade, adequação, necessidade, segurança, prevenção, transparência, responsabilização) viram estas regras:

### 1. Classificar antes de modelar

- Marque cada campo novo como `publico`, `pessoal` ou `sensivel`: comentário no schema, atributo no modelo ou tabela de classificação no repo.
- Prefira separar dado sensível em tabela própria, com acesso mais restrito, em vez de colunas soltas numa tabela larga.

### 2. Minimizar (necessidade)

- Colete e devolva só o necessário para a finalidade. DTO de listagem não leva CPF completo, diagnóstico nem endereço "por garantia".
- Mascare na saída quando o dado completo não for necessário: `***.456.789-**`.
- Exportação (CSV, relatório) é tratamento novo: só os campos que a finalidade exige, e com registro de quem exportou.

### 3. Nada de dado pessoal onde não deve estar

- **Log:** nunca CPF, CNS, nome com diagnóstico, corpo de requisição com dado de paciente, token ou senha. Logue o identificador interno (id técnico) e o evento. Configure o logger para redigir campos conhecidos.
- **URL e query string:** nunca CPF, nome ou dado de saúde, porque acabam em log de proxy, histórico e referer. Use POST ou id opaco.
- **Mensagem de erro e stack trace devolvidos ao cliente:** sem dado pessoal e sem detalhe interno.
- **Ambiente de desenvolvimento e teste:** sem cópia de produção com dado real. Use dado sintético ou base anonimizada.
- **Prompt para IA e serviço externo:** não envie dado pessoal real de paciente a ferramenta externa sem base legal e contrato.

### 4. Controle de acesso por finalidade

- Autorização por perfil **e** por vínculo: o profissional vê o paciente da unidade ou do atendimento dele, não a base inteira.
- Checagem no backend, em todo endpoint; esconder botão no frontend não é controle.
- Consulta por CPF ou nome em massa (busca aberta) é vetor de vazamento: limite, pagine e audite.

### 5. Trilha de auditoria (responsabilização)

- Registre **leitura** de dado sensível, não só escrita: quem, quando, qual registro, por qual funcionalidade.
- A auditoria não pode ser apagada nem editada pelo mesmo perfil que acessa o dado.
- A própria trilha contém dado pessoal: proteja e defina retenção.
- O art. 37 obriga controlador e operador a manter registro das operações de tratamento.

### 6. Segurança desde a concepção (art. 46)

- Medidas técnicas e administrativas desde a concepção do produto até a execução (art. 46, §2º), e sistemas estruturados para atender aos requisitos de segurança (art. 49).
- Criptografia em trânsito (TLS) e em repouso para dado sensível, segredo em vault (`vault-factory`), backup protegido.
- Na avaliação de gravidade de um incidente, pesa a favor do controlador ter tornado os dados ininteligíveis a terceiros (art. 48, §3º). Criptografia bem feita reduz o dano.

### 7. Retenção e eliminação (arts. 15 e 16)

- Todo dado pessoal precisa de prazo ou condição de término: finalidade alcançada, fim do período, pedido do titular ou determinação da ANPD.
- Depois do término, eliminar, salvo conservação por obrigação legal (por exemplo, prazo de guarda de prontuário), estudo por órgão de pesquisa, ou uso exclusivo do controlador com dado anonimizado.
- **No código:** rotina de expurgo ou anonimização com prazo configurável, e não `DELETE` manual. O prazo é dado de negócio; pergunte, não invente.

### 8. Direitos do titular (art. 18)

O sistema precisa permitir, por processo ou por funcionalidade: confirmar se há tratamento, dar acesso, corrigir, anonimizar/bloquear/eliminar o desnecessário, informar com quem houve compartilhamento e revogar consentimento. Ao modelar, garanta que dá para **achar todos os dados de um titular** (inclusive em log, cópia e integração) e **corrigi-los ou eliminá-los** sem quebrar integridade referencial.

## Incidente de segurança com dado pessoal

1. **Conter** o vazamento e preservar evidência (logs, trilha de auditoria). Não apague nada para "limpar".
2. **Avisar já** o responsável pelo sistema e o encarregado (DPO) do órgão. A decisão de comunicar é do controlador, não do desenvolvedor.
3. **Levantar os fatos** que a comunicação exige (art. 48, §1º): natureza dos dados afetados, titulares envolvidos, medidas de segurança que existiam, riscos, motivo de eventual demora e medidas para reverter ou mitigar.
4. **Prazo:** a lei diz "prazo razoável, conforme definido pela autoridade nacional" (art. 48, §1º). A página de orientação da ANPD sobre a Resolução CD/ANPD nº 15/2024 informa **três dias úteis** para comunicar à ANPD e ao titular, ressalvado prazo de legislação específica, com complementação fundamentada em até vinte dias úteis.
   - Nesta pesquisa, esse prazo foi conferido só na página da ANPD (gov.br/anpd, "Comunicação de Incidente de Segurança"). O texto da resolução não carregou. Confira o texto vigente antes de usar o prazo numa resposta real.
5. **Nem todo incidente precisa ser comunicado:** segundo a ANPD, a comunicação cabe quando o incidente está confirmado, envolve dado pessoal sujeito à LGPD e pode acarretar risco ou dano relevante aos titulares (art. 48, caput). Dado sensível de saúde pesa para o lado do risco relevante.

## Checklist de revisão

- [ ] Campos novos classificados (público, pessoal ou sensível)?
- [ ] Só os campos necessários na entrada, na saída e na exportação?
- [ ] Nenhum dado pessoal em log, URL, mensagem de erro ou ambiente de teste?
- [ ] Autorização no backend, por perfil e por vínculo, em todo endpoint novo?
- [ ] Leitura de dado sensível auditada?
- [ ] Prazo de retenção definido, ou registrado como pendência para o usuário?
- [ ] Uso novo de dado pessoal (finalidade, compartilhamento, exportação) levado ao usuário para confirmar base legal?
- [ ] Dá para localizar, corrigir e eliminar os dados de um titular?

## Fontes

- Lei 13.709/2018: https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709.htm
- ANPD, Comunicação de Incidente de Segurança: https://www.gov.br/anpd/pt-br/assuntos/comunicacao-de-incidentes-de-seguranca-cis
- Resolução CD/ANPD nº 15/2024 (Regulamento de Comunicação de Incidente de Segurança), publicada no DOU em 24/04/2024.
