#!/usr/bin/env python3
"""Aciona ctvl-setup-env.sh num pseudo-terminal (ele é interativo e recusa stdin que não seja tty).

Uso: pty_setup_env.py <ctvl-setup-env.sh> <apelido> <host> <usuário> <ca|-> <resposta-tls|-> <base>
A senha vem da variável de ambiente PTY_SETUP_PASSWORD (nunca de argumento). Imprime tudo que o script
mostrou no terminal e sai com o código do script. Só para os testes offline: nenhum segredo real.
"""
import os
import pty
import select
import sys
import time


def main(argv):
    script, alias, host, user, ca, tls, base = argv
    password = os.environ["PTY_SETUP_PASSWORD"]
    steps = [("Host do vault", host), ("Usuário ADMIN", user), ("Senha ADMIN", password),
             ("CA bundle", "" if ca == "-" else ca)]
    if tls != "-":
        steps.append(("verificação TLS", tls))
    steps.append(("Base da API admin", base))
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp("bash", ["bash", script, alias])
    seen = b""
    buf = b""
    deadline = time.time() + 20
    for prompt, answer in steps:
        needle = prompt.encode()
        while needle not in buf:
            if time.time() > deadline:
                os.kill(pid, 9)
                sys.stdout.write(seen.decode("utf-8", "replace"))
                sys.stdout.write("\n[pty] TEMPO ESGOTADO esperando: %s\n" % prompt)
                return 99
            r, _, _ = select.select([fd], [], [], 0.5)
            if r:
                try:
                    chunk = os.read(fd, 4096)
                except OSError:
                    chunk = b""
                if not chunk:
                    break
                seen += chunk
                buf += chunk
        buf = buf.split(needle, 1)[-1] if needle in buf else buf
        time.sleep(0.05)
        os.write(fd, (answer + "\r").encode())
    while True:
        r, _, _ = select.select([fd], [], [], 0.5)
        if r:
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                break
            if not chunk:
                break
            seen += chunk
        elif time.time() > deadline:
            os.kill(pid, 9)
            break
    _, status = os.waitpid(pid, 0)
    sys.stdout.write(seen.decode("utf-8", "replace"))
    return os.waitstatus_to_exitcode(status)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
