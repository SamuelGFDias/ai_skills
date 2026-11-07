#!/usr/bin/env python3
"""Testes do guard.py. Rodar: python3 -I claude-guard-hooks/scripts/test_guard.py"""
import json
import os
import subprocess
import sys

GUARD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "guard.py")


def run(event, env_extra=None):
    env = dict(os.environ)
    env.pop("CLAUDE_GUARD_DISABLE", None)
    env.update(env_extra or {})
    out = subprocess.run([sys.executable, "-I", GUARD], input=json.dumps(event), capture_output=True,
                         text=True, env=env, timeout=10)
    assert out.returncode == 0, out.stderr
    if not out.stdout.strip():
        return None
    return json.loads(out.stdout)["hookSpecificOutput"]["permissionDecision"]


def bash(cmd):
    return {"hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": cmd}}


CASES = [
    # (descrição, evento, decisão esperada)
    ("commit com Co-Authored-By Claude", bash('git commit -m "feat: x\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"'), "deny"),
    ("heredoc com Generated with Claude Code", bash("gh pr create --title t --body \"$(cat <<'EOF'\nresumo\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\nEOF\n)\""), "deny"),
    ("commit limpo", bash('git commit -m "feat(arquiteto): modo hibrido"'), None),
    ("co-autor humano", bash('git commit -m "fix: y\n\nCo-Authored-By: Maria <maria@x.com>"'), None),
    ("menção a Claude fora de commit", bash('echo "Co-Authored-By: Claude" > notas.txt'), None),
    ("--no-verify no commit", bash('git commit --no-verify -m "x"'), "deny"),
    ("--no-verify no push", bash("git push --no-verify origin main"), "deny"),
    ("op read solto", bash("op read 'op://Private/Bambu_Lan_Code/notesPLain'"), "deny"),
    ("op read capturado", bash("BAMBU_ACCESS_CODE=\"$(op read 'op://Private/Bambu_Lan_Code/notesPLain')\" python3 -I x.py status"), None),
    ("op read em pipe seguro", bash("op read 'op://Private/registry/password' | docker login reg.example --username u --password-stdin"), None),
    ("op read em pipe para cat", bash("op read 'op://Private/x/y' | cat"), "deny"),
    ("op read em pipe para tee", bash("op read 'op://Private/x/y' | tee /tmp/s"), "deny"),
    ("echo do segredo", bash("echo $BAMBU_ACCESS_CODE"), "deny"),
    ("printenv de token", bash("printenv GITHUB_TOKEN"), "deny"),
    ("teste de variável definida", bash('[ -n "$GITHUB_TOKEN" ] && echo definido'), None),
    ("rm -rf home", bash("rm -rf ~/"), "ask"),
    ("rm -rf curinga", bash("rm -rf *"), "ask"),
    ("rm -rf diretório específico", bash("rm -rf build/output"), None),
    ("rm -rf node_modules", bash("rm -rf ./node_modules"), None),
    ("push force", bash("git push --force origin main"), "ask"),
    ("push -f", bash("git push -f"), "ask"),
    ("push force-with-lease", bash("git push --force-with-lease origin feat/x"), None),
    ("reset hard", bash("git reset --hard HEAD~1"), "ask"),
    ("reset soft", bash("git reset --soft HEAD~1"), None),
    ("clean -fd", bash("git clean -fd"), "ask"),
    ("checkout -- .", bash("git checkout -- ."), "ask"),
    ("checkout de arquivo", bash("git checkout -- src/a.cs"), None),
    ("branch -D", bash("git branch -D feat/velha"), "ask"),
    ("branch -d", bash("git branch -d feat/velha"), None),
    ("drop table", bash('psql -c "DROP TABLE pacientes"'), "ask"),
    ("delete sem where", bash('psql -c "DELETE FROM pacientes;"'), "ask"),
    ("delete com where", bash('psql -c "DELETE FROM pacientes WHERE id = 1;"'), None),
    ("comando comum", bash("dotnet test tests/App.Tests"), None),
    ("write com token GitHub", {"tool_name": "Write", "tool_input": {"file_path": "/r/app/config.json", "content": "{\"t\": \"ghp_" + "a" * 36 + "\"}"}}, "deny"),
    ("edit com chave privada", {"tool_name": "Edit", "tool_input": {"file_path": "/r/k.pem", "old_string": "x", "new_string": "-----BEGIN OPENSSH PRIVATE KEY-----"}}, "deny"),
    ("write .env.example", {"tool_name": "Write", "tool_input": {"file_path": "/r/.env.example", "content": "KEY=sk-ant-" + "x" * 30}}, None),
    ("write código comum", {"tool_name": "Write", "tool_input": {"file_path": "/r/a.cs", "content": "var x = 1;"}}, None),
    ("entrada inválida", {"tool_name": "Bash", "tool_input": "texto"}, None),
    # --- regressão da revisão de segurança (security-audit, modo orientação, 2026-11-07) ---
    # C1: opções globais do git
    ("C1 git -C push force", bash("git -C /srv/repo push --force"), "ask"),
    ("C1 git -C reset hard", bash("git -C /srv/repo reset --hard HEAD~1"), "ask"),
    ("C1 git -C clean -fd", bash("git -C /srv/repo clean -fd"), "ask"),
    ("C1 git -C branch -D", bash("git -C /srv/repo branch -D feat"), "ask"),
    ("C1 git -C status", bash("git -C /srv/repo status --short"), None),
    # C2: op read capturado mas impresso, e segundo op read no mesmo comando
    ("C2 echo de $(op read)", bash("echo \"$(op read 'op://Private/x/pw')\""), "deny"),
    ("C2 segundo op read solto", bash("X=\"$(op read a)\" cmd; op read b"), "deny"),
    # C3: no-verify curto, depois de ';' na mensagem e depois de heredoc
    ("C3 commit -n", bash("git commit -n -m 'x'"), "deny"),
    ("C3 commit -nm", bash("git commit -nm 'x'"), "deny"),
    ("C3 ; na mensagem", bash("git commit -m 'fix: a; b' --no-verify"), "deny"),
    ("C3 depois de heredoc", bash("git commit -m \"$(cat <<'EOF'\nfeat: x\n\nEOF\n)\" --no-verify"), "deny"),
    ("C3 push -n é dry-run", bash("git push -n origin main"), None),
    # C5: variantes de rm
    ("C5 rm -Rf ~", bash("rm -Rf ~"), "ask"),
    ("C5 rm -rf /*", bash("rm -rf /*"), "ask"),
    ("C5 rm -rf \"$HOME\"", bash("rm -rf \"$HOME\""), "ask"),
    ("C5 rm -r --force ~", bash("rm -r --force ~"), "ask"),
    # C6: outras formas de git destrutivo
    ("C6 checkout .", bash("git checkout ."), "ask"),
    ("C6 push +refspec", bash("git push origin +main"), "ask"),
    ("C6 push -uf", bash("git push -uf origin main"), "ask"),
    ("C6 push -u", bash("git push -u origin feat/x"), None),
    # FP1: atribuição fora do segmento do commit
    ("FP1 grep no log depois do commit", bash("git commit -m \"fix\" && git log -1 | grep -c 'Co-Authored-By: Claude'"), None),
    # FP2: mensagem que cita a flag
    ("FP2 mensagem cita --no-verify", bash("git commit -m 'docs: explica a regra --no-verify do guard'"), None),
    # FP3: segredo por pipe a consumidor
    ("FP3 echo token | gh auth", bash("echo \"$GH_TOKEN\" | gh auth login --with-token"), None),
    ("FP3 printf senha | docker login", bash("printf '%s' \"$DOCKER_PASSWORD\" | docker login --password-stdin"), None),
    ("FP3 echo token | cat", bash("echo \"$GH_TOKEN\" | cat"), "deny"),
    # FP4: SQL só em cliente de banco
    ("FP4 commit com truncate", bash("git commit -m 'fix: truncate text in label'"), None),
    ("FP4 rg drop table", bash("rg -i 'drop table' src/"), None),
    ("FP4 psql drop", bash("psql -h db -c \"DROP TABLE x\""), "ask"),
    # heredoc sem aspas com o rodapé
    ("commit -F - com heredoc", bash("git commit -F - <<EOF\nfeat: x\n\nCo-Authored-By: Claude <noreply@anthropic.com>\nEOF"), "deny"),
]


def main():
    failures = 0
    for desc, event, expected in CASES:
        got = run(event)
        ok = got == expected
        failures += not ok
        print(f"{'ok  ' if ok else 'FALHA'} {desc}: esperado={expected} obtido={got}")
    got = run(bash("git reset --hard"), {"CLAUDE_GUARD_DISABLE": "destructive"})
    ok = got is None
    failures += not ok
    print(f"{'ok  ' if ok else 'FALHA'} regra desligada por env: obtido={got}")
    extra = 1

    # C4: mensagem vinda de arquivo (-F / --body-file)
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        footer = "feat: x\n\nCo-Authored" + "-By: Claude <noreply@anthropic.com>\n"
        with open(os.path.join(d, "msg.txt"), "w", encoding="utf-8") as f:
            f.write(footer)
        with open(os.path.join(d, "limpo.txt"), "w", encoding="utf-8") as f:
            f.write("feat: x\n")
        for desc, cmd, expected in [
            ("C4 commit -F arquivo com rodapé", "git commit -F msg.txt", "deny"),
            ("C4 pr --body-file com rodapé", "gh pr create --title t --body-file msg.txt", "deny"),
            ("C4 commit -F arquivo limpo", "git commit -F limpo.txt", None),
        ]:
            ev = bash(cmd)
            ev["cwd"] = d
            got = run(ev)
            ok = got == expected
            failures += not ok
            extra += 1
            print(f"{'ok  ' if ok else 'FALHA'} {desc}: esperado={expected} obtido={got}")

    # C8: comando enorme termina rápido (corte em 64 KB)
    import time
    t0 = time.time()
    run(bash("git push x " * 30000))
    dt = time.time() - t0
    ok = dt < 3
    failures += not ok
    extra += 1
    print(f"{'ok  ' if ok else 'FALHA'} C8 comando de {len('git push x ' * 30000) // 1024} KB em {dt:.2f}s")

    total = len(CASES) + extra
    print(f"\n{total - failures}/{total} casos passaram")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
