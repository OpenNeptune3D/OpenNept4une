#!/usr/bin/env python3
"""Smoke tests for printer-confs/generate_conf.py."""

from __future__ import annotations

import contextlib
import io
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Optional

REPO = Path(__file__).resolve().parents[1]
CONF_DIR = REPO / "printer-confs"
OUTPUT_CFG = CONF_DIR / "output.cfg"

if str(CONF_DIR) not in sys.path:
    sys.path.insert(0, str(CONF_DIR))

import generate_conf  # noqa: E402


_TMP_HOME: Optional[tempfile.TemporaryDirectory] = None
_ORIG_HOME: Optional[str] = None


def setUpModule() -> None:
    """Point HOME at an empty dir so the host's printer.cfg SAVE_CONFIG block
    (and MCU_ID.cfg) never leaks into generated output."""
    global _TMP_HOME, _ORIG_HOME
    _ORIG_HOME = os.environ.get("HOME")
    _TMP_HOME = tempfile.TemporaryDirectory()
    os.environ["HOME"] = _TMP_HOME.name


def tearDownModule() -> None:
    if _ORIG_HOME is None:
        os.environ.pop("HOME", None)
    else:
        os.environ["HOME"] = _ORIG_HOME
    if _TMP_HOME is not None:
        _TMP_HOME.cleanup()


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
        self.assertIn("usage:", (result.stdout + result.stderr).lower())

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

    def test_usb_c_lights_override_quietly(self) -> None:
        # USB-C lights: frame light on a host GPIO, part light a plain lamp on THR.
        for model, current in MODELS:
            with self.subTest(model=model, current=current):
                err = io.StringIO()
                with contextlib.redirect_stderr(err):
                    text = generate_conf.render(model, current, "usb-c")
                self.assertRegex(text, r"\[output_pin Frame_Light\]\npin: rpi:gpiochip2/gpio2\n")
                self.assertRegex(text, r"\[output_pin Part_Light\]\npin: THR:PB10\n")
                self.assertNotIn("[neopixel", text)
                self.assertNotIn("light_pin", err.getvalue())

    def test_ribbon_lights_unchanged(self) -> None:
        self.assertIn("pin: PB7", generate_conf.render("n4pro", "1.2", "ribbon"))
        self.assertIn("pin: rpi:gpiochip2/gpio15", generate_conf.render("n4max", None, "ribbon"))

    def test_usb_c_n4_blowers_follow_m106(self) -> None:
        for model in ("n4", "n4pro"):
            with self.subTest(model=model):
                text = generate_conf.render(model, "1.2", "usb-c")
                self.assertIn("[multi_pin part_cooling_fans]\npins: THR:PB1, THR:PB11", text)
                self.assertIn("[fan]\npin: multi_pin:part_cooling_fans", text)
                self.assertNotIn("[fan_generic fan2]", text)

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

    def test_backslashes_in_values_are_literal(self) -> None:
        # Values must be inserted verbatim, not interpreted as re.sub escapes.
        original = generate_conf.collect_values

        def patched(model, current, toolhead):
            values, origin = original(model, current, toolhead)
            values["x_hold_current"] = "0.5 ; a\\d\\1 b"
            return values, origin

        generate_conf.collect_values = patched
        try:
            out = generate("n4pro", "0.8")
        finally:
            generate_conf.collect_values = original
        self.assertIn("a\\d\\1 b", out)


if __name__ == "__main__":
    unittest.main()
