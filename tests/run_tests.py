"""Run with: python -m pip install -r tests/requirements.txt && python tests/run_tests.py"""

import argparse
from pathlib import Path

from lupa.lua51 import LuaRuntime


parser = argparse.ArgumentParser(description="Run LanguageScout's Lua 5.1 tests.")
parser.add_argument("--addon-root", type=Path, default=Path(__file__).resolve().parents[1])
args = parser.parse_args()

lua = LuaRuntime(unpack_returned_tuples=True)
# Match WoW's byte-oriented patterns, regardless of the host's system locale.
lua.execute('os.setlocale("C", "ctype")')
lua.globals().addonRoot = args.addon_root.resolve().as_posix()
lua.execute(Path(__file__).with_name("run.lua").read_text(encoding="utf-8"))
