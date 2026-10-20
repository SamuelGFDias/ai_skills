# 06 — Autostart no login

- O serviço sobe sozinho pelo systemd (`systemctl --user is-enabled t3code` → `enabled`). Para isso, o `linger` precisa estar ativo se a sessão do usuário não estiver logada: `loginctl show-user $USER -p Linger`.
- O app desktop sobe no login pelo arquivo `~/.config/autostart/t3code.desktop`. Remova o arquivo para desligar.
- O `tailscaled` deve estar habilitado no boot: `systemctl is-enabled tailscaled`. A configuração do `serve` persiste após reinício.
