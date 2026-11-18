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


def run_cli(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(CONF_DIR / "generate_conf.py"), *args],
        cwd=REPO,
        capture_output=True,
        text=True,
        check=False,
    )


class ProbeVariants(unittest.TestCase):
    def test_stock_keeps_probe_and_adds_no_include(self) -> None:
        text = generate_conf.render("n4pro", "1.2", "ribbon")
        self.assertIn("\n[probe]\n", text)
        self.assertNotIn("[include cartographer.cfg]", text)
        self.assertNotIn("[include beacon.cfg]", text)
        self.assertEqual(PLACEHOLDER_RE.findall(text), [])

    def test_scanning_probe_drops_probe_and_includes_last(self) -> None:
        for probe in ("cartographer", "beacon", "eddy"):
            for toolhead in ("ribbon", "usb-c"):
                with self.subTest(probe=probe, toolhead=toolhead):
                    text = generate_conf.render("n4pro", "1.2", toolhead, probe)
                    self.assertNotRegex(text, r"(?m)^\[probe\]")
                    self.assertIn("endstop_pin:probe:z_virtual_endstop", text)
                    include = f"[include {probe}.cfg]"
                    self.assertIn(include, text)
                    self.assertGreater(text.index(include),
                                       text.index("[include user_settings.cfg]"))
                    # The probe block's options must not leak into the
                    # preceding section.
                    self.assertNotIn("samples_tolerance_retries", text)
                    self.assertIn("[bed_mesh]", text)
                    self.assertEqual(PLACEHOLDER_RE.findall(text), [])

    def test_print_start_uses_home_hook(self) -> None:
        text = generate_conf.render("n4", "0.8", "ribbon")
        self.assertIn("[gcode_macro _PRINT_START_HOME]", text)
        start = text.index("[gcode_macro PRINT_START]")
        body = text[start:text.index("[gcode_macro PRINT_END]")]
        self.assertIn("_PRINT_START_HOME", body)
        self.assertNotRegex(body, r"(?m)^\s*G28\s*$")

    def test_unknown_probe_rejected(self) -> None:
        result = run_cli("n4pro", "1.2", "--probe", "bltouch")
        self.assertNotEqual(result.returncode, 0)

    def test_missing_probe_cfg_is_an_error(self) -> None:
        result = run_cli("n4pro", "1.2", "--probe", "cartographer",
                         "--out", os.path.join(os.environ["HOME"], "out.cfg"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--seed-probe-cfg", result.stderr)


class ProbeSeeding(unittest.TestCase):
    def setUp(self) -> None:
        self.dev = tempfile.TemporaryDirectory()
        serial = Path(self.dev.name) / "usb-Cartographer_stm32g431xx_TEST-if00"
        serial.touch()
        self.serial = str(serial)
        self.orig_globs = dict(generate_conf.PROBE_SERIAL_GLOBS)
        generate_conf.PROBE_SERIAL_GLOBS["cartographer"] = \
            str(Path(self.dev.name) / "usb-Cartographer_*")
        self.target = Path(generate_conf.probe_cfg_path("cartographer"))

    def tearDown(self) -> None:
        generate_conf.PROBE_SERIAL_GLOBS.clear()
        generate_conf.PROBE_SERIAL_GLOBS.update(self.orig_globs)
        if self.target.exists():
            self.target.unlink()
        self.dev.cleanup()

    def seed(self) -> None:
        with contextlib.redirect_stdout(io.StringIO()):
            generate_conf.seed_probe_cfg("n4pro", "cartographer", "0,22")

    def test_seed_values_match_known_good_n4pro(self) -> None:
        self.seed()
        text = self.target.read_text(encoding="utf-8")
        self.assertIn(f"serial: {self.serial}", text)
        self.assertIn("screw1: 32.5, 180.5", text)
        self.assertIn("screw3: 202.5, 10.5", text)
        self.assertIn("zero_reference_position: 117.5, 95.5", text)
        self.assertIn("home_xy_position: 117.5, 95.5", text)
        self.assertIn("mesh_max: 220, 211", text)
        self.assertIn("calibrate_y: 95.5", text)
        self.assertRegex(text, r"(?m)^x_offset: 0\b")
        self.assertRegex(text, r"(?m)^y_offset: 22\b")
        self.assertEqual(PLACEHOLDER_RE.findall(text), [])

    def test_seed_never_overwrites(self) -> None:
        self.target.parent.mkdir(parents=True, exist_ok=True)
        self.target.write_text("# mine\n", encoding="utf-8")
        self.seed()
        self.assertEqual(self.target.read_text(encoding="utf-8"), "# mine\n")

    def test_seeded_file_satisfies_generation(self) -> None:
        self.seed()
        out = os.path.join(os.environ["HOME"], "carto-out.cfg")
        with contextlib.redirect_stdout(io.StringIO()):
            generate_conf.generate_conf("n4pro", "1.2", "ribbon", out, "cartographer")
        text = Path(out).read_text(encoding="utf-8")
        self.assertIn("probe: cartographer", text.splitlines()[0])
        self.assertIn("[include cartographer.cfg]", text)


class CartographerAccel(unittest.TestCase):
    V4 = "/dev/serial/by-id/usb-Cartographer_stm32g431xx_ABC-if00"
    V3 = "/dev/serial/by-id/usb-Cartographer_stm32f042x6_ABC-if00"

    def render(self, accel: str, toolhead: str = "ribbon", serial: str = V4) -> str:
        return generate_conf.render_probe_cfg("n4pro", "cartographer", (0.0, 22.0),
                                              serial, accel, toolhead)

    def test_version_from_usb_name(self) -> None:
        self.assertEqual(generate_conf.cartographer_version_from_serial(self.V4), "v4")
        self.assertEqual(generate_conf.cartographer_version_from_serial(self.V3), "v3")
        self.assertIsNone(generate_conf.cartographer_version_from_serial("/dev/x"))

    def test_v4_ribbon_enables_accel_and_tester(self) -> None:
        text = self.render("v4")
        self.assertRegex(text, r"(?m)^\[adxl345 hotend\]\ncs_pin: cartographer:PA0$")
        self.assertRegex(text, r"(?m)^\[resonance_tester\]\naccel_chip: adxl345 hotend$")
        self.assertIn("    117.5, 117.5, 20", text)

    def test_v3_uses_pa3(self) -> None:
        text = self.render("v3", serial=self.V3)
        self.assertRegex(text, r"(?m)^cs_pin: cartographer:PA3$")
        self.assertNotRegex(text, r"(?m)^cs_pin: cartographer:PA0$")

    def test_usb_c_keeps_toolhead_resonance_tester(self) -> None:
        text = self.render("v4", toolhead="usb-c")
        self.assertRegex(text, r"(?m)^\[adxl345 hotend\]$")
        self.assertNotRegex(text, r"(?m)^\[resonance_tester\]$")
        self.assertIn("#[resonance_tester]", text)

    def test_none_leaves_everything_commented(self) -> None:
        text = self.render("none")
        self.assertNotRegex(text, r"(?m)^\[adxl345")
        self.assertNotRegex(text, r"(?m)^\[resonance_tester\]")
        self.assertNotRegex(text, r"(?m)^cs_pin")

    def test_choice_contradicting_usb_name_is_refused(self) -> None:
        dev = tempfile.TemporaryDirectory()
        self.addCleanup(dev.cleanup)
        serial = Path(dev.name) / "usb-Cartographer_stm32g431xx_ABC-if00"
        serial.touch()
        target = Path(generate_conf.probe_cfg_path("cartographer"))
        self.addCleanup(lambda: target.unlink() if target.exists() else None)
        with self.assertRaises(generate_conf.GenerationError) as ctx:
            generate_conf.seed_probe_cfg("n4pro", "cartographer", "0,22", str(serial), "v3")
        self.assertIn("V4", str(ctx.exception))
        self.assertFalse(target.exists())
        with contextlib.redirect_stdout(io.StringIO()):
            generate_conf.seed_probe_cfg("n4pro", "cartographer", "0,22", str(serial), "none")
        self.assertNotRegex(target.read_text(encoding="utf-8"), r"(?m)^cs_pin")


class HandEdits(unittest.TestCase):
    BASE = """[printer]
kinematics: cartesian
max_velocity: 250

[extruder]
max_temp: 300
pid_kp = 20.0

[probe]
pin: ^PA11

[gcode_macro PRINT_START]
gcode:
    G28
    BED_MESH_CALIBRATE

[include user_settings.cfg]
"""

    def edits(self, current: str, new: str, base: Optional[str] = None,
              probe: str = "stock") -> list:
        return [m for _s, m in generate_conf.find_hand_edits(current, new, base, probe)]

    def test_user_edit_reported_upstream_change_not(self) -> None:
        current = self.BASE.replace("max_temp: 300", "max_temp: 330")
        new = self.BASE.replace("max_velocity: 250", "max_velocity: 300")
        found = self.edits(current, new, self.BASE)
        self.assertEqual(found, ["[extruder] max_temp: 330  (update has 300)"])

    def test_without_baseline_everything_different_is_reported(self) -> None:
        current = self.BASE.replace("max_temp: 300", "max_temp: 330")
        new = self.BASE.replace("max_velocity: 250", "max_velocity: 300")
        found = self.edits(current, new)
        self.assertEqual(len(found), 2)

    def test_formatting_and_comments_do_not_count(self) -> None:
        current = (self.BASE.replace("max_temp: 300", "max_temp:300   ; hotter later")
                   .replace("    G28\n", "    G28    ; home\n\n"))
        self.assertEqual(self.edits(current, self.BASE, self.BASE), [])

    def test_added_sections_includes_and_macro_edits(self) -> None:
        current = (self.BASE.replace("    BED_MESH_CALIBRATE\n", "    BED_MESH_CALIBRATE ADAPTIVE=1\n")
                   + "[include cartographer.cfg]\n\n[fan_generic extra]\npin: PA1\n")
        found = self.edits(current, self.BASE, self.BASE)
        self.assertIn("[include cartographer.cfg] include is not in the update", found)
        self.assertIn("[fan_generic extra] section is not in the update", found)
        self.assertTrue(any(m.startswith("[gcode_macro PRINT_START] gcode edited") for m in found))

    def test_removed_option_that_update_restores(self) -> None:
        current = self.BASE.replace("max_velocity: 250\n", "")
        found = self.edits(current, self.BASE, self.BASE)
        self.assertEqual(found, ["[printer] max_velocity: you removed it; the update sets 250"])

    def test_save_config_values_ignored(self) -> None:
        current = (self.BASE.replace("pid_kp = 20.0", "pid_kp = 25.0")
                   + "#*# <---------------------- SAVE_CONFIG ---------------------->\n"
                   + "#*# [extruder]\n#*# pid_kp = 25.0\n")
        self.assertEqual(self.edits(current, self.BASE, self.BASE), [])

    def test_probe_section_dropped_by_probe_mode_is_not_an_edit(self) -> None:
        new = generate_conf.drop_section(self.BASE, "probe")
        self.assertEqual(self.edits(self.BASE, new, self.BASE, probe="cartographer"), [])
        self.assertTrue(self.edits(self.BASE, new, None, probe="stock"))

    def test_cli_exit_status(self) -> None:
        tmp = Path(os.environ["HOME"])
        cur, new = tmp / "cur.cfg", tmp / "new.cfg"
        new.write_text(self.BASE, encoding="utf-8")
        cur.write_text(self.BASE, encoding="utf-8")
        self.assertEqual(run_cli("--check-edits", str(cur), str(new),
                         "--baseline", str(tmp / "none.cfg")).returncode, 0)
        cur.write_text(self.BASE.replace("max_temp: 300", "max_temp: 330"), encoding="utf-8")
        result = run_cli("--check-edits", str(cur), str(new),
                         "--baseline", str(tmp / "none.cfg"))
        self.assertEqual(result.returncode, 2)
        self.assertIn("max_temp: 330", result.stdout)
        self.assertIn("user_settings.cfg", result.stdout)


class EddySeeding(unittest.TestCase):
    def setUp(self) -> None:
        self.dev = tempfile.TemporaryDirectory()
        self.orig_globs = dict(generate_conf.PROBE_SERIAL_GLOBS)
        generate_conf.PROBE_SERIAL_GLOBS["eddy"] = \
            str(Path(self.dev.name) / "usb-Klipper_rp2040_*")
        self.target = Path(generate_conf.probe_cfg_path("eddy"))

    def tearDown(self) -> None:
        generate_conf.PROBE_SERIAL_GLOBS.clear()
        generate_conf.PROBE_SERIAL_GLOBS.update(self.orig_globs)
        if self.target.exists():
            self.target.unlink()
        self.dev.cleanup()

    def add_device(self, name: str) -> str:
        path = Path(self.dev.name) / name
        path.touch()
        return str(path)

    def test_seed_eddy(self) -> None:
        serial = self.add_device("usb-Klipper_rp2040_E66138935F-if00")
        with contextlib.redirect_stdout(io.StringIO()):
            generate_conf.seed_probe_cfg("n4", "eddy", "0,21.42")
        text = self.target.read_text(encoding="utf-8")
        self.assertIn(f"serial: {serial}", text)
        self.assertIn("[probe_eddy_current btt_eddy]", text)
        self.assertIn("[temperature_probe btt_eddy]", text)
        self.assertRegex(text, r"(?m)^y_offset: 21.42\b")
        self.assertIn("descend_z: 0.5", text)
        self.assertIn("zero_reference_position: 117.5, 96.08", text)
        self.assertEqual(PLACEHOLDER_RE.findall(text), [])

    def test_two_rp2040_devices_need_explicit_serial(self) -> None:
        self.add_device("usb-Klipper_rp2040_AAAA-if00")
        pick = self.add_device("usb-Klipper_rp2040_BBBB-if00")
        with self.assertRaises(generate_conf.GenerationError) as ctx:
            generate_conf.seed_probe_cfg("n4", "eddy", "0,20")
        self.assertIn("--probe-serial", str(ctx.exception))
        with contextlib.redirect_stdout(io.StringIO()):
            generate_conf.seed_probe_cfg("n4", "eddy", "0,20", pick)
        self.assertIn(f"serial: {pick}", self.target.read_text(encoding="utf-8"))



class ProbeGeometryPerModel(unittest.TestCase):
    def test_models_get_their_own_bed_values(self) -> None:
        expected = {
            "n4": ("117.5, 95.5", "220, 211", "117.5, 117.5, 20"),
            "n4plus": ("165, 85", "300.75, 315.45", "165, 165, 20"),
            "n4max": ("215.5, 193", "397, 404", "215, 215, 20"),
        }
        for model, (home, mesh_max, res) in expected.items():
            with self.subTest(model=model):
                v = generate_conf.probe_geometry(model, (0.0, 22.0))
                self.assertEqual(v["home_xy_position"], home)
                self.assertEqual(v["mesh_max"], mesh_max)
                self.assertEqual(v["resonance_point"], res)
        counts = [generate_conf.probe_geometry(m, (0.0, 22.0))["probe_count"]
                  for m in ("n4", "n4plus", "n4max")]
        self.assertEqual(len(set(counts)), 3, counts)

    def test_stock_offset_reproduces_stock_profile(self) -> None:
        # Fed the stock probe's own offset, the derivation must land on the
        # stock homing spot, screw points and (within 1 mm) mesh bounds.
        so = generate_conf.stock_probe_offset()
        for model in ("n4", "n4pro", "n4plus", "n4max"):
            with self.subTest(model=model):
                v = generate_conf.probe_geometry(model, so)
                prof = generate_conf.parse_kv_file(str(CONF_DIR / model / f"{model}.cfg"))
                hx, hy = (float(p) for p in prof["safe_z_home_xy_position"].split(","))
                gx, gy = (float(p) for p in v["home_xy_position"].split(","))
                self.assertAlmostEqual(gx, hx, places=2)
                self.assertAlmostEqual(gy, hy, places=2)
                sx, sy = (float(p) for p in prof["bed_mesh_max"].split(","))
                mx, my = (float(p) for p in v["mesh_max"].split(","))
                self.assertLessEqual(abs(mx - sx), 1.0)
                self.assertLessEqual(abs(my - sy), 1.0)
                screws = (CONF_DIR / model / "section_screw_tilt.cfg").read_text()
                for line in v["screw_tilt"].splitlines():
                    if line.startswith("screw") and ":" in line and "_" not in line.split(":")[0]:
                        x, y = (float(p) for p in line.split(":")[1].split(","))
                        self.assertRegex(screws, rf"{line.split(':')[0]}:\s*{x:g},\s*{y:g}")

    def test_unreachable_offset_rejected(self) -> None:
        with self.assertRaises(generate_conf.GenerationError):
            generate_conf.probe_geometry("n4", (0.0, 300.0))


class ProbeSerialAutofill(unittest.TestCase):
    def setUp(self) -> None:
        self.dev = tempfile.TemporaryDirectory()
        self.orig_globs = dict(generate_conf.PROBE_SERIAL_GLOBS)
        generate_conf.PROBE_SERIAL_GLOBS["cartographer"] = \
            str(Path(self.dev.name) / "usb-Cartographer_*")
        self.target = Path(generate_conf.probe_cfg_path("cartographer"))
        self.target.parent.mkdir(parents=True, exist_ok=True)

    def tearDown(self) -> None:
        generate_conf.PROBE_SERIAL_GLOBS.clear()
        generate_conf.PROBE_SERIAL_GLOBS.update(self.orig_globs)
        for p in (self.target, Path(f"{self.target}.bak")):
            if p.exists():
                p.unlink()
        self.dev.cleanup()

    def device(self, name: str) -> str:
        path = Path(self.dev.name) / name
        path.touch()
        return str(path)

    def write(self, mcu_body: str) -> None:
        self.target.write_text(
            "[mcu cartographer]\n" + mcu_body + "\n[cartographer]\nmcu: cartographer\n",
            encoding="utf-8")

    def fill(self, override: Optional[str] = None) -> str:
        with contextlib.redirect_stdout(io.StringIO()), \
                contextlib.redirect_stderr(io.StringIO()):
            generate_conf.ensure_probe_serial("cartographer", override)
        return self.target.read_text(encoding="utf-8")

    def test_placeholder_serial_is_filled(self) -> None:
        dev = self.device("usb-Cartographer_stm32g431xx_ABC-if00")
        self.write("serial: /dev/serial/by-id/<your-probe>  # set me\nrestart_method: command\n")
        text = self.fill()
        self.assertIn(f"serial: {dev}\n", text)
        self.assertIn("restart_method: command", text)
        self.assertTrue(Path(f"{self.target}.bak").exists())

    def test_missing_serial_line_is_added(self) -> None:
        dev = self.device("usb-Cartographer_stm32g431xx_ABC-if00")
        self.write("restart_method: command\n")
        self.assertIn(f"[mcu cartographer]\nserial: {dev}\n", self.fill())

    def test_working_serial_left_alone(self) -> None:
        mine = self.device("usb-Cartographer_stm32g431xx_MINE-if00")
        self.device("usb-Cartographer_stm32g431xx_OTHER-if00")
        self.write(f"serial: {mine}\n")
        before = self.target.read_text(encoding="utf-8")
        self.assertEqual(self.fill(), before)

    def test_can_probe_left_alone(self) -> None:
        self.device("usb-Cartographer_stm32g431xx_ABC-if00")
        self.write("#serial:\ncanbus_uuid: 0123456789ab\n")
        before = self.target.read_text(encoding="utf-8")
        self.assertEqual(self.fill(), before)

    def test_ambiguous_devices_leave_file_unchanged(self) -> None:
        self.device("usb-Cartographer_stm32g431xx_A-if00")
        self.device("usb-Cartographer_stm32g431xx_B-if00")
        self.write("serial: /dev/serial/by-id/gone\n")
        before = self.target.read_text(encoding="utf-8")
        self.assertEqual(self.fill(), before)

    def test_explicit_serial_wins(self) -> None:
        self.device("usb-Cartographer_stm32g431xx_A-if00")
        pick = self.device("usb-Cartographer_stm32g431xx_B-if00")
        self.write("serial: /dev/serial/by-id/gone\n")
        self.assertIn(f"serial: {pick}\n", self.fill(pick))


if __name__ == "__main__":
    unittest.main()
