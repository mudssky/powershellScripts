#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "litellm>=1.81.0",
# ]
# ///
"""Coding Plan 窗口预热脚本入口。"""

from __future__ import annotations

from window_warmer_lib.cli import main

if __name__ == "__main__":
    raise SystemExit(main())
