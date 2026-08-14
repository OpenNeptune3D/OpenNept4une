#!/usr/bin/env python3
"""Smoke tests for printer-confs/generate_conf.py."""

from __future__ import annotations

import contextlib
import io
import re
import subprocess
import sys
import unittest
from pathlib import Path
from typing import Optional

REPO = Path(__file__).resolve().parents[1]
CONF_DIR = REPO / "printer-confs"
OUTPUT_CFG = CONF_DIR / "output.cfg"

if str(CONF_DIR) not in sys.path:
    sys.path.insert(0, str(CONF_DIR))

import generate_conf  # noqa: E402


PLACEHOLDER_RE = re.compile(r"\{\{\s*\w+\s*\}\}")

MODELS = (
    ("n4", "0.8"),
    ("n4", "1.2"),
    ("n4pro", "0.8"),
    ("n4pro", "1.2"),
    ("n4plus", None),
    ("n4max", None),
)


def generate(model: str, current: Optional[str]) -> str:
    if OUTPUT_CFG.exists():
        OUTPUT_CFG.unlink()
    with contextlib.redirect_stdout(io.StringIO()):
        generate_conf.generate_conf(model, current)
    return OUTPUT_CFG.read_text(encoding="utf-8")


class GenerateConfSmoke(unittest.TestCase):
    def test_cli_requires_model(self) -> None:
        result = subprocess.run(
            [sys.executable, str(CONF_DIR / "generate_conf.py")],
            cwd=REPO,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Usage:", result.stdout + result.stderr)

    def test_cli_rejects_unknown_model(self) -> None:
        result = subprocess.run(
            [sys.executable, str(CONF_DIR / "generate_conf.py"), "not-a-model"],
            cwd=REPO,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ERROR:", result.stdout + result.stderr)

    def test_all_supported_models_generate(self) -> None:
        for model, current in MODELS:
            with self.subTest(model=model, current=current):
                text = generate(model, current)
                self.assertTrue(text.strip(), f"{model} produced an empty config")
                leftover = PLACEHOLDER_RE.findall(text)
                self.assertEqual(leftover, [], f"{model} left placeholders: {leftover}")
                self.assertIn("[printer]", text)
                self.assertIn("[gcode_macro PRINT_START]", text)
                self.assertIn("[include user_settings.cfg]", text)
                self.assertIn(f"printer_model: {model}", text.splitlines()[0])

    def test_n4max_bounds(self) -> None:
        text = generate("n4max", None)
        self.assertIn("position_max: 430", text)
        self.assertIn("position_max: 505", text)
        self.assertIn("mesh_max: 397,404", text)
        self.assertIn("x_offset: -24.25", text)
        self.assertIn("y_offset: 20.45", text)
        self.assertIn("home_xy_position: 239.75,194.55", text)
        self.assertIn("calibrate_start_x: 25", text)
        self.assertIn("calibrate_end_x: 395", text)
        self.assertIn("run_current: 1.0", text)
        self.assertIn("run_current: 1.3", text)
        self.assertIn("driver_SGTHRS: 90", text)
        self.assertIn("driver_SGTHRS: 80", text)
        self.assertIn("BED_HEAT_SOAK_MINUTES", text)
        self.assertNotIn("heater_bed_outer", text)

    def test_n4plus_bounds(self) -> None:
        text = generate("n4plus", None)
        self.assertIn("position_max: 330", text)
        self.assertIn("position_max: 405", text)
        self.assertIn("run_current: 1.1", text)
        self.assertNotIn("heater_bed_outer", text)

    def test_n4_and_n4pro_currents(self) -> None:
        n4_08 = generate("n4", "0.8")
        self.assertIn("position_max: 235", n4_08)
        self.assertIn("run_current: 0.8", n4_08)
        self.assertNotIn("heater_bed_outer", n4_08)

        n4_12 = generate("n4", "1.2")
        self.assertIn("run_current: 1.2", n4_12)

        n4pro = generate("n4pro", "0.8")
        self.assertIn("[heater_generic heater_bed_outer]", n4pro)
        self.assertIn("variable_small_print", n4pro)
        self.assertIn("PID_Tune_Outer_BED", n4pro)

    def test_missing_override_exits(self) -> None:
        result = subprocess.run(
            [sys.executable, str(CONF_DIR / "generate_conf.py"), "n4max", "1.2"],
            cwd=REPO,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ERROR:", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
