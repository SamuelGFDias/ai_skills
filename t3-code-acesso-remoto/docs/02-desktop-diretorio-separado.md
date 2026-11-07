# 02 — App desktop apontando para outro diretório
> `<HOME>` = seu diretório home absoluto (valor de `echo $HOME`).


O app desktop passa a usar `T3CODE_HOME=~/.t3-desktop`, sem tocar no serviço.

1. Crie o diretório: `mkdir -p ~/.t3-desktop`.
2. Atualize **os dois** atalhos que abrem o app (menu e autostart), trocando `Exec`:
   ```ini
   Exec=env T3CODE_HOME=<HOME>/.t3-desktop <HOME>/Applications/T3-Code.AppImage %U
   ```
   Arquivos: `~/.local/share/applications/t3-code.desktop` e `~/.config/autostart/t3code.desktop`. Em autostart, retire o `%U`.
3. Valide: `desktop-file-validate <arquivo>` e `update-desktop-database ~/.local/share/applications`.
4. Feche o app desktop (SIGTERM no PID exato, nunca `pkill -f` com padrão que case o próprio shell) e reabra pelo atalho.
5. Confirme a separação: `~/.t3-desktop/userdata/server-runtime.json` deve existir com um `pid` diferente do `pid` de `~/.t3/userdata/server-runtime.json`.
