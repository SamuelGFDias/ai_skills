#!/usr/bin/env python3
"""Ponte de exemplo entre o widget e o mundo de fora.

Uso:
  bridge.py status            -> {"items": [...]}
  bridge.py toggle <id>       -> {"items": [<só o item alterado>]}

Sempre imprime UMA linha JSON: {"items": [...]} ou {"error": "..."}.
Troque o estado em arquivo abaixo pela sua fonte real (API, dispositivo, comando).
"""
import json
import os
import sys

STATE = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
                     "__ID__", "state.json")
DEFAULT = [
    {"id": "a", "name": "Item A", "on": True, "level": 70},
    {"id": "b", "name": "Item B", "on": False, "level": 30},
]


class BridgeError(Exception):
    pass


def load():
    try:
        with open(STATE, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return [dict(i) for i in DEFAULT]


def save(items):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(items, fh)
    os.replace(tmp, STATE)  # nunca deixa um JSON pela metade


def main(argv):
    try:
        if not argv:
            raise BridgeError("informe um comando: status | toggle <id> | level <id> <0-100>")
        items = load()
        cmd, args = argv[0], argv[1:]
        if cmd == "status":
            result = items
        elif cmd in ("toggle", "level"):
            if len(args) != (1 if cmd == "toggle" else 2):
                raise BridgeError("argumentos inválidos para %s" % cmd)
            found = [i for i in items if i["id"] == args[0]]
            if not found:
                raise BridgeError("item desconhecido: %s" % args[0])
            if cmd == "toggle":
                found[0]["on"] = not found[0]["on"]
            else:
                try:
                    found[0]["level"] = max(0, min(100, int(float(args[1]))))
                except ValueError:
                    raise BridgeError("valor inválido: %r" % args[1])
            save(items)
            result = found
        else:
            raise BridgeError("comando desconhecido: %s" % cmd)
        print(json.dumps({"items": result}, ensure_ascii=False))
        return 0
    except BridgeError as exc:
        print(json.dumps({"error": str(exc)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
