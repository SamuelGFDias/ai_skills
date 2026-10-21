---
name: instalacao-appimage-linux
description: Instala um AppImage no Linux (copia para ~/Applications, configura ícone e atalho do menu via tema hicolor, valida, testa abertura sem deixar processos órfãos e resolve ícone duplicado na dock do GNOME). Use quando o usuário pedir para instalar, atualizar, configurar o ícone/atalho de, ou diagnosticar um AppImage (.AppImage) em Linux.
---

# Skill: instalacao-appimage-linux

**Tipo:** open-source — procedimento genérico para qualquer AppImage. Os caminhos são relativos a `$HOME`.

## Quando usar

- Usuário pede para instalar um `.AppImage` baixado (ex.: em `~/Downloads`).
- Ícone do app não aparece, aparece genérico ou aparece como caminho no atalho.
- Dock do GNOME mostra o mesmo app duas vezes (um fixado sem indicador de execução, outro com o ponto).
- App abre com erro de "home/data directory em uso" depois de um teste.

## Script

`scripts/install.sh` faz os passos 1 a 7 de forma idempotente. Uso:

```bash
~/.config/ai/skills/instalacao-appimage-linux/scripts/install.sh \
  ~/Downloads/<App>.AppImage <nome-curto> [app-id]
```

- `nome-curto`: nome do arquivo em `~/Applications/` e do atalho (ex.: `t3code`). Sem espaços.
- `app-id`: o `StartupWMClass` da janela (ex.: `com.t3tools.T3Code`). Se não souber, rode sem ele, abra o app uma vez e siga o passo 6. Depois rode de novo com o app-id.

O script **não abre o app**. Teste a abertura pelo menu (passo 8).

## Passos (o que o script faz e o que confirmar)

### 1. Verificar o arquivo
- Confira que é um AppImage: bytes 8 a 9 devem ser `AI`. O script já faz essa checagem.
- Se o usuário forneceu um hash ou assinatura do fornecedor, confira antes de instalar.
- Trate o arquivo como não confiável. Não execute nada que venha de dentro dele além do próprio AppImage.

### 2. Instalar em `~/Applications/<nome-curto>.AppImage`
- `cp` (não `mv`) para manter o original em `~/Downloads`. Pergunte ao usuário se quer apagar o original depois. Não apague sem perguntar.
- `chmod +x`.
- Teste o runtime com `<AppImage> --appimage-version`. Resposta com "AppImage runtime version" indica que o arquivo é válido.

### 3. Checar FUSE
- AppImage tipo 2 monta a imagem via `libfuse.so.2`. Verifique com `ldconfig -p | grep libfuse.so.2`.
- Se faltar, o app pode não abrir. Opções:
  - Fedora: `! sudo dnf install -y fuse-libs`
  - Debian/Ubuntu: `! sudo apt install libfuse2t64` (ou `libfuse2` em versões antigas)
  - Sem instalar nada: rodar com `--appimage-extract-and-run`. Use isso para teste, e não como solução definitiva no atalho, a menos que o usuário prefira.
- Instalação de pacote precisa de `sudo`. Sugira o comando com `!` e não rode você.

### 4. Extrair `.desktop` e ícones para um diretório temporário próprio
- Use `mktemp -d` e rode `<AppImage> --appimage-extract '<padrão>'` dentro dele, para `*.desktop`, `*.png` e `usr/share/icons/*`.
- Não execute scripts nem binários de dentro do diretório extraído.

### 5. Instalar os ícones no tema hicolor, não como caminho absoluto
- Copie cada `usr/share/icons/hicolor/<N>x<N>/apps/<nome>.png` para `~/.local/share/icons/hicolor/<N>x<N>/apps/<nome>.png`. Use o nome que está no campo `Icon=` do `.desktop` extraído.
- Motivo: o atalho deve usar `Icon=<nome>`, que é o padrão do tema. Caminho absoluto funciona no menu, mas não é o padrão e confunde outras ferramentas.
- Se não houver tema hicolor, copie o PNG da raiz para `512x512/apps/`.

### 6. Criar o atalho e definir o `StartupWMClass`
- Arquivo: `~/.local/share/applications/<nome-curto>.desktop`.
- `Exec=<caminho absoluto do AppImage> %U`. Nunca use `AppRun` ou um caminho relativo. O atalho do menu não tem o `PATH` do shell.
- `Icon=<nome do tema>`.
- `StartupWMClass=<app-id>`. Este é o ponto que causou o ícone duplicado na dock. O app-id é o que a janela registra no Wayland/X11, não o nome do arquivo.
- **Como descobrir o app-id:** depois da primeira abertura, procure em `~/.local/share/applications/` um `.desktop` novo criado pelo próprio app (costuma ser `com.<empresa>.<App>.desktop`, com `NoDisplay=true`). O nome desse arquivo, sem `.desktop`, é o app-id. Use-o no `StartupWMClass`.
- Se o app não criar esse arquivo, use o nome que o app declara no próprio `package.json`/`id` quando souber, ou teste pelo comportamento da dock (passo 9).

### 7. Validar
- `desktop-file-validate <arquivo>` deve passar.
- `update-desktop-database ~/.local/share/applications`.
- `gtk-update-icon-cache -q -t -f ~/.local/share/icons/hicolor`.

### 8. Testar a abertura sem deixar órfãos
**Não conclua que o app abre só porque `timeout` retornou 124.** O `timeout` mata a janela, mas o processo de backend do app pode continuar vivo, com a porta e o diretório de dados ocupados. Isso já aconteceu:
- sintoma: "This T3 home is unavailable — Another T3 Code server ... is using this data directory" ao abrir o app depois de um teste;
- causa: o servidor de backend (filho do AppImage) ficou órfão, reparentado ao `systemd --user`.

Procedimento correto:
1. Abra pelo menu (ou em background com `nohup`), espere alguns segundos.
2. Veja os processos: `ps -eo pid,ppid,etime,cmd | grep -i <nome>`.
3. Veja as portas que o app abriu: `ss -ltnp | grep <porta>`. O arquivo de runtime do app (ex.: `~/.<app>/userdata/server-runtime.json`) costuma informar `pid` e `port`.
4. Depois de qualquer teste, encerre os processos que você iniciou (`kill <pid>`), incluindo backend e monitores filhos, e confirme com `ps` e `ss` que a porta foi liberada.
5. Se o usuário já estiver com o app aberto, não mate a janela dele. Oriente-o a fechar e reabrir.

### 9. Ícone duplicado na dock (GNOME)
- Sintoma: um ícone fixado sem o ponto de execução, e outro com o ponto (a janela).
- Diagnóstico:
  - `gsettings get org.gnome.shell favorite-apps` mostra os favoritos.
  - Compare o app-id da janela (passo 6) com o `StartupWMClass` do atalho fixado.
- Correção: o atalho fixado deve declarar o app-id como `StartupWMClass`. Não remova o favorito se não precisar. Basta ajustar o `.desktop` e rodar `update-desktop-database`.
- Se ainda aparecer duplicado: feche o app, troque o favorito para o atalho certo e, em Wayland, faça logout/login para o GNOME reler os atalhos.

### 10. Atualizar ou remover
- **Atualizar:** rode o script de novo com o AppImage novo e o mesmo `nome-curto`. Mantenha o mesmo nome para não perder o favorito.
- **Remover:** apague `~/Applications/<nome-curto>.AppImage`, `~/.local/share/applications/<nome-curto>.desktop`, os PNGs `~/.local/share/icons/hicolor/*/apps/<nome-icone>.png`, e rode `update-desktop-database` e `gtk-update-icon-cache`. Confirme antes de apagar.

## Erros comuns

| Sintoma | Causa | Ação |
|---|---|---|
| App não abre, erro sobre `libfuse.so.2` | FUSE 2 ausente | Passo 3 |
| Ícone genérico no menu | `Icon=` aponta para caminho que não existe, ou não há cache de ícones | Passos 5 e 7 |
| Dois ícones na dock | `StartupWMClass` diferente do app-id | Passo 9 |
| "home/data directory em uso" | Backend órfão de um teste anterior | Passo 8 |
| Atalho some do menu | Arquivo `.desktop` com `NoDisplay=true` ou `Exec` inválido | Passos 6 e 7 |

## Relatório ao final

Informe o usuário em português: caminho instalado, caminho do atalho, quantos tamanhos de ícone foram instalados, se o FUSE está presente, o app-id usado, e o resultado do teste de abertura (incluindo se algum processo órfão foi encerrado). Não diga que o app abre sem ter verificado os processos.
