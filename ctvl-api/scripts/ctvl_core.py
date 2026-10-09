#!/usr/bin/env python3
"""Ponto de entrada do motor Python. Use os scripts bash (ctvl.sh e ctvl-*.sh), que carregam credenciais."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.dont_write_bytecode = True

from ctvlpy.cli import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
