#!/usr/bin/env python3
"""Unit tests for scripts/fxdev.py:  python3 scripts/test_fxdev.py

No test ever calls xdotool, touches the real install or the real game dir: every
subprocess goes through FakeRunner (xdotool and git are faked; only `luajit` runs for
real, on temp files, because the SavedVariables parser is the thing under test).
"""
import hashlib
import io
import json
import os
import random
import re
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fxdev  # noqa: E402
from fxdev import RunResult  # noqa: E402
from PIL import Image, ImageChops, ImageDraw  # noqa: E402

WOW = "World of Warcraft"
CORE_SV = '''ForteXorcistDB = {
	["version"] = 1,
	["diag"] = {
		["casts"] = 66,
		["timerCasts"] = {
			["plain"] = 2649,
			["secret"] = 0,
		},
	},
	["errors"] = {
		["session"] = 3,
		["list"] = {
			{
				["kind"] = "error",
				["msg"] = "Forte_Timer/Rows.lua:88: attempt to index\\nline two \\"quoted\\" |cffff0000red|r",
				["stack"] = "Rows.lua:88\\nCore.lua:12",
				["count"] = 2,
				["first"] = 1762980000,
				["last"] = 1762980100,
				["session"] = 3,
			}, -- [1]
			{
				["kind"] = "blocked",
				["msg"] = "ADDON_ACTION_BLOCKED ReloadUI",
				["count"] = 1,
				["first"] = 1762980200,
				["last"] = 1762980200,
				["session"] = 3,
			}, -- [2]
		},
	},
	["cooldownLearned"] = {
		[12345] = 6.5,
		[67890] = 30,
	},
	["timer"] = {
		["point"] = "CENTER",
		["x"] = -12.5,
		["y"] = 100,
		["expand"] = false,
	},
	["probesEvents"] = {
		["casts"] = { "SECRET", 12345, 12345 },
		["restricts"] = {},
	},
}
'''
DEV_SV = '''ForteDevDB = {
	["stamp"] = "STAMP",
	["build"] = "70888",
	["runId"] = 6,
	["runs"] = {
		{ ["id"] = 5, ["stamp"] = "old", ["suite"] = "ooc", ["pass"] = 3, ["fail"] = 0, ["skip"] = 0 },
		{
			["id"] = 6, ["stamp"] = "STAMP", ["suite"] = "ooc", ["started"] = 1, ["finished"] = 2,
			["combat"] = false, ["pass"] = 2, ["fail"] = 1, ["skip"] = 0,
			["tests"] = {
				{ ["name"] = "load census", ["status"] = "pass", ["detail"] = "" },
				{ ["name"] = "frames", ["status"] = "fail", ["detail"] = "no anchor" },
			},
		},
	},
	["commands"] = {},
}
'''


# --------------------------------------------------------------------------
# fakes
# --------------------------------------------------------------------------
class Clock:
    def __init__(self):
        self.t = 1_800_000_000.0
        self.sleeps = []
        self.on_sleep = None

    def now(self):
        return self.t

    def sleep(self, s):
        self.sleeps.append(s)
        self.t += s
        if self.on_sleep:
            self.on_sleep(self)


class FakeRunner:
    """xdotool + git are fakes; luajit really runs (SV parsing is under test)."""

    def __init__(self, windows=("111",), git_sha="abc1234", dirty=False):
        self.calls = []
        self.envs = []
        self.focus = WOW
        self.windows = list(windows)
        self.names = {w: WOW for w in windows}
        self.activate_works = True
        self.lose_after = None          # "slash" | "type" | "return"
        self.typed, self.executed = [], []
        self.pending = None
        self.on_exec = None
        self.git_sha, self.dirty = git_sha, dirty
        self.luajit_calls = 0

    @property
    def x_calls(self):
        return [c for c in self.calls if c[0] == "xdotool"]

    @property
    def sent(self):
        return [c for c in self.x_calls if c[1] in ("key", "type")]

    def __call__(self, argv, env=None, timeout=None, input=None, limits=None):
        self.calls.append(list(argv))
        prog = argv[0]
        if prog == "xdotool":
            self.envs.append(env)
            return self._x(argv[1:])
        if prog == "git":
            if "rev-parse" in argv:
                return RunResult(0, self.git_sha + "\n", "")
            if "status" in argv:
                return RunResult(0, " M addon/Forte_Core/x.lua\n" if self.dirty else "", "")
        if prog == "luajit":
            self.luajit_calls += 1
            return fxdev.real_run(argv, env=env, timeout=timeout, input=input, limits=limits)
        raise AssertionError(f"test tried to run {argv!r}")

    def _x(self, a):
        cmd = a[0]
        if cmd == "search":
            return RunResult(0 if self.windows else 1, "".join(w + "\n" for w in self.windows), "")
        if cmd == "getwindowname":
            return RunResult(0, self.names.get(a[1], "") + "\n", "")
        if cmd == "windowactivate":
            if self.activate_works:
                self.focus = WOW
            return RunResult(0, "", "")
        if a[:2] == ["getwindowfocus", "getwindowname"]:
            return RunResult(0, self.focus + "\n", "")
        if cmd == "key":
            if a[1] == "Return":
                self.executed.append(self.pending)
                if self.on_exec:
                    self.on_exec(self.pending)
                self.pending = None
            elif a[1] == "slash":
                self.pending = "/"
            if self.lose_after == {"slash": "slash", "Return": "return"}.get(a[1]):
                self.focus = "Some Terminal"
            return RunResult(0, "", "")
        if cmd == "type":
            self.typed.append(a[-1])
            self.pending = "/" + a[-1]
            if self.lose_after == "type":
                self.focus = "Some Terminal"
            return RunResult(0, "", "")
        raise AssertionError(f"unexpected xdotool {a!r}")


def png_bytes(img):
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return buf.getvalue()


def make_screen(W, H, scale=1.0, combat=0, group=0, running=0, finished=0, failed=0, errors=0,
                run_id=0, noise=0, jpeg=0, beacon=True, decoys=False, seed=7):
    """A synthetic game screenshot with the PLAN 11.11 beacon at the top-left corner."""
    rng = random.Random(seed)
    small = Image.new("RGB", (64, 27))
    small.putdata([(rng.randrange(0, 110), rng.randrange(0, 110), rng.randrange(0, 110))
                   for _ in range(64 * 27)])
    img = small.resize((W, H), Image.BILINEAR)
    d = ImageDraw.Draw(img)
    cell = 6 * H / 768 * scale
    if decoys:                                   # things that must not fool the decoder
        d.rectangle([int(W * 0.10), 2, int(W * 0.10) + 13, 15], fill=(255, 0, 255))   # lone magenta
        d.rectangle([int(W * 0.105), 30, int(W * 0.105) + 2, 32], fill=(255, 0, 255))  # tiny pink
        d.rectangle([int(W * 0.108), 2, int(W * 0.108) + 9, 11], fill=(0, 255, 255))   # lone cyan
        x = int(W * 0.065)
        d.rectangle([x, 60, x + 9, 69], fill=(255, 0, 255))                      # a wrong-sized pair
        d.rectangle([x + 100, 60, x + 109, 69], fill=(0, 255, 255))
    if beacon:
        bits = [combat, group, running, finished, failed, errors] + \
               [(run_id >> (7 - i)) & 1 for i in range(8)]
        cols = [(255, 0, 255)] + [(255, 255, 255) if b else (0, 0, 0) for b in bits] + [(0, 255, 255)]
        for i, col in enumerate(cols):
            d.rectangle([round(i * cell), 0, round((i + 1) * cell) - 1, round(cell) - 1], fill=col)
    if noise:
        rw, rh = int(W * 0.14), int(H * 0.08)
        reg = img.crop((0, 0, rw, rh))
        chans = [ImageChops.add(c, Image.effect_noise((rw, rh), noise), 1.0, -128) for c in reg.split()]
        img.paste(Image.merge("RGB", chans), (0, 0))
    if jpeg:
        buf = io.BytesIO()
        img.save(buf, "JPEG", quality=jpeg)
        buf.seek(0)
        img = Image.open(buf).convert("RGB")
    return img


class Env:
    """A temp repo + game dir + proc fixture + Ctx wired to a FakeRunner."""

    def __init__(self, test, windows=("111",), dirty=False, with_dev=True, game_running=True):
        self.tmp = tempfile.TemporaryDirectory()
        test.addCleanup(self.tmp.cleanup)
        t = self.tmp.name
        self.repo = os.path.join(t, "repo")
        self.wow = os.path.join(t, "wow", "_forever_")
        self.addons = os.path.join(self.wow, "Interface", "AddOns")
        self.acct = os.path.join(self.wow, "WTF", "Account", "ACC#1", "SavedVariables")
        self.shots = os.path.join(self.wow, "Screenshots")
        self.proc = os.path.join(t, "proc")
        for d in (self.addons, self.acct, self.shots, self.proc, os.path.join(self.proc, "999")):
            os.makedirs(d)
        with open(os.path.join(self.proc, "999", "cmdline"), "wb") as fh:
            fh.write(b"/bin/other\0--x\0")
        if game_running:
            os.makedirs(os.path.join(self.proc, "123"))
            with open(os.path.join(self.proc, "123", "cmdline"), "wb") as fh:
                fh.write(b"proton\0waitforexitandrun\0AppId=2691180173\0")
        self.build_repo(with_dev)
        self.write(os.path.join(self.acct, "Forte_Core.lua"), CORE_SV)
        self.runner = FakeRunner(windows=windows, dirty=dirty)
        self.clock = Clock()
        self.ctx = fxdev.Ctx(
            env={"FX_WOW_DIR": self.wow, "FX_XAUTHORITY": "/tmp/xauth_test", "FX_STATE_DIR":
                 os.path.join(t, "state")},
            run=self.runner, sleep=self.clock.sleep, now=self.clock.now, root=self.repo,
            proc_root=self.proc, uid=os.getuid(), run_dir=os.path.join(t, "run"))

    @staticmethod
    def write(path, text, mode="w"):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, mode) as fh:
            fh.write(text)

    def build_repo(self, with_dev):
        r = self.repo
        toc = "## Interface: 16001\n## Title: X\nCore/Init.lua\n"
        w = self.write
        for name, files in {
            "Forte_Core": {"Core/Init.lua": "-- init\n", "tests/t.lua": "t", "docs/n.md": "n",
                           "Fonts/x.otf": "otf", "Fonts/x.ttf": "ttf", ".gitignore": "g",
                           "Core/tests/deep.lua": "deep"},
            "Forte_Hunter": {"Data/Hunter.lua": "hunter\n"},
        }.items():
            w(f"{r}/addon/{name}/{name}.toc", toc)
            w(f"{r}/addon/{name}/{name}_Camelot.toc", toc)
            for rel, txt in files.items():
                w(f"{r}/addon/{name}/{rel}", txt)
        w(f"{r}/addon/NotForte/NotForte.toc", toc)          # not a Forte_* addon
        w(f"{r}/addon/NotForte/a.lua", "x")
        w(f"{r}/addon/Forte_NoToc/readme.txt", "no toc")      # Forte_* without a toc
        if with_dev:
            toc_d = "## Interface: 16001\n## SavedVariables: ForteDevDB\nDevStamp.lua\nDevCommands.lua\nCore.lua\n"
            for t in ("Forte_Dev.toc", "Forte_Dev_Camelot.toc"):
                w(f"{r}/dev/Forte_Dev/{t}", toc_d)
            w(f"{r}/dev/Forte_Dev/Core.lua", "-- dev core\n")
            w(f"{r}/dev/Forte_Dev/Suites/a.lua", "-- suite\n")
            w(f"{r}/dev/Forte_Dev/tests/z.lua", "no")
            w(f"{r}/dev/Forte_Dev/DevStamp.lua", 'ForteDevStamp = "PLACEHOLDER"\n')
        # a foreign addon the tool must never touch
        w(f"{self.addons}/Other_Addon/data.lua", "keep me\n")

    def snapshot_other(self):
        p = os.path.join(self.addons, "Other_Addon", "data.lua")
        with open(p, "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest(), os.stat(p).st_mtime_ns

    def install_files(self):
        out = set()
        for base, _d, files in os.walk(self.addons):
            for f in files:
                out.add(os.path.relpath(os.path.join(base, f), self.addons).replace(os.sep, "/"))
        return out

    def next_shot(self, **kw):
        n = len([f for f in os.listdir(self.shots)]) + 1
        W, H = kw.pop("size", (1920, 1080))
        img = make_screen(W, H, **kw)
        img.save(os.path.join(self.shots, f"WoWScrnShot_111226_2143{n:02d}.png"))

    def bump(self, path, text):
        """Rewrite an SV file so its (mtime_ns, size) certainly differ."""
        old = os.stat(path).st_mtime_ns if os.path.exists(path) else 0
        self.write(path, text)
        os.utime(path, ns=(old + 10_000_000_000, old + 10_000_000_000))

    def run(self, argv):
        out = io.StringIO()
        code = fxdev.main(argv, ctx=self.ctx, out=out)
        return code, json.loads(out.getvalue())


# --------------------------------------------------------------------------
# whitelist and deny-list
# --------------------------------------------------------------------------
class Whitelist(unittest.TestCase):
    ACCEPT = [
        "/reload", "/fx", "/fx test", "/fx errors clear", "/fxdev", "/fxdev shot",
        "/fxdev selftest ooc", "/run print(1)", "/run Screenshot()", "/run print(GetBuildInfo())",
        "/run print(ForteXorcistDB.errors)", "/console screenshotFormat png",
        "/console screenshotFormat jpeg", "/chatlog", "/combatlog", "/chatlog on",
        "/run " + "x" * 235,                          # exactly 240 chars
    ]
    REJECT = [
        ("", "empty"), ("reload", "no slash"), (" /reload", "leading space"),
        ("/RELOAD", "case"), ("/reloadui", "not the whitelisted word"),
        ("/fxx", "prefix lookalike"), ("/fxdevx", "prefix lookalike"), ("/runx 1", "needs space"),
        ("/run", "no payload"), ("/run ", "empty payload"), ("/run    ", "blank payload"),
        ("/cast Fireball", "gameplay"), ("/s hello", "chat"), ("/say hi", "chat"),
        ("/w bob hi", "whisper"), ("/logout", "session"), ("/quit", "session"), ("/script x", "script"),
        ("/target bob", "target"), ("/console", "bare console"),
        ("/console screenshotFormat", "no value"), ("/console screenshotFormat ", "blank value"),
        ("/console screenshotFormat png /quit", "chained"), ("/console SetCVar x", "other console"),
        ("/reload\n/quit", "newline"), ("/reload\r", "CR"), ("/run print(1)\n", "newline"),
        ("/run print(1)\tx", "tab"), ("/fx\x00", "NUL"), ("/fx \x1b", "ESC"), ("/fx \x7f", "DEL"),
        ("/run " + "x" * 236, "241 chars"), ("/fx \u00e9", "non-ASCII"), ("/fx \u2028", "line separator"),
        ("\u2215reload", "lookalike slash"), (None, "not a string"), (5, "not a string"),
    ]

    def test_accept(self):
        for cmd in self.ACCEPT:
            with self.subTest(cmd=cmd[:50]):
                ok, why = fxdev.command_verdict(cmd)
                self.assertTrue(ok, why)
        self.assertEqual(len("/run " + "x" * 235), 240)

    def test_reject(self):
        for cmd, label in self.REJECT:
            with self.subTest(label=label, cmd=repr(cmd)[:40]):
                ok, why = fxdev.command_verdict(cmd)
                self.assertFalse(ok)
                self.assertTrue(why)
                with self.assertRaises(fxdev.Refused):
                    fxdev.check_command(cmd)

    def test_allow_unsafe_never_relaxes_the_whitelist_or_shape_rules(self):
        for cmd in ("/cast Fireball", "/reload\n", "/run " + "x" * 300, "reload", "/fx \u00e9"):
            self.assertFalse(fxdev.command_verdict(cmd, allow_unsafe=True)[0], cmd)


class DenyList(unittest.TestCase):
    SPEC_NAMES = ["SendChatMessage", "C_ChatInfo.Send", "C_ChatInfo.SendAddonMessage", "CastSpell",
                  "CastSpellByName", "UseAction", "TargetUnit", "MoveForward", "MoveForwardStart",
                  "JumpOrAscend", "RunMacro", "RunMacroText", "InviteUnit", "AcceptTrade",
                  "PickupContainerItem", "UseContainerItem", "C_Container.UseContainerItem", "Logout",
                  "Quit", "ForceQuit", "DeleteCursorItem", "SendMail", "BuyMerchantItem", "StartDuel"]

    def test_spec_names_are_refused(self):
        for n in self.SPEC_NAMES:
            with self.subTest(name=n):
                ok, why = fxdev.command_verdict(f"/run {n}('x')")
                self.assertFalse(ok)
                self.assertIn("deny-listed", why)

    def test_whole_table_is_refused_in_call_position(self):
        for n in fxdev.DENY_EXACT:
            self.assertFalse(fxdev.command_verdict(f"/run {n}()")[0], n)
        for n in fxdev.DENY_PREFIX:
            self.assertFalse(fxdev.command_verdict(f"/run {n}Foo()")[0], n)

    def test_evasions_that_are_caught(self):
        for payload in ("sendchatmessage('x')", "SENDCHATMESSAGE('x')", '_G["SendChatMessage"]("x")',
                        'local f=_G["Send".."ChatMessage"]', "C_ChatInfo . SendAddonMessage('a','b')",
                        "C_ChatInfo:SendAddonMessage('a')", "C_ChatInfo['Send'..'AddonMessage']()",
                        "loadstring('Quit()')()", "getfenv(0).Quit()", "RunScript('x')",
                        "local q=Quit q()", "print(1) Logout()", "C_Container.UseContainerItem(0,1)",
                        "C_Container . PickupContainerItem(0,1)"):
            with self.subTest(payload=payload):
                self.assertFalse(fxdev.command_verdict("/run " + payload)[0])

    def test_dev_payloads_pass(self):
        for payload in ("print(1)", "Screenshot()", "print(GetBuildInfo())", "print(InCombatLockdown())",
                        "print(ForteXorcist.Compat.PlainOrNil(1))", "print(issecretvalue(1))",
                        "print(C_AddOns.GetAddOnMetadata('Forte_Core','Version'))",
                        "print(C_Spell.GetSpellInfo(1))", "print('Quitting is a word')",
                        "ForteXorcistDB.errors=nil", "print(#ForteDevDB.runs)",
                        "print(C_AddOns.IsAddOnLoaded('Forte_Dev'))", "print(LoadAddOnX)"):
            with self.subTest(payload=payload):
                self.assertTrue(fxdev.command_verdict("/run " + payload)[0])

    def test_allow_unsafe_skips_only_the_deny_list(self):
        self.assertFalse(fxdev.command_verdict("/run Quit()")[0])
        self.assertTrue(fxdev.command_verdict("/run Quit()", allow_unsafe=True)[0])

    def test_deny_list_only_applies_to_run(self):
        self.assertTrue(fxdev.command_verdict("/fx Quit")[0])

    def test_type_verb_with_deny_hit_sends_nothing(self):
        e = Env(self)
        code, out = e.run(["type", "/run SendChatMessage('x','SAY')"])
        self.assertEqual(code, 2)
        self.assertFalse(out["ok"])
        self.assertEqual(e.runner.calls, [])


# --------------------------------------------------------------------------
# focus guard + combat guard
# --------------------------------------------------------------------------
class FocusGuard(unittest.TestCase):
    def test_happy_path_sequence_and_env(self):
        e = Env(self)
        res = fxdev.send_command(e.ctx, "/run print(1)")
        self.assertEqual(res["sent"], "/run print(1)")
        self.assertEqual(e.runner.sent, [["xdotool", "key", "slash"],
                                         ["xdotool", "type", "--delay", "70", "run print(1)"],
                                         ["xdotool", "key", "Return"]])
        self.assertEqual(e.runner.executed, ["/run print(1)"])
        self.assertIn(0.6, e.clock.sleeps)
        self.assertIn(0.3, e.clock.sleeps)
        self.assertEqual(e.runner.x_calls[0], ["xdotool", "search", "--name", WOW])
        self.assertIn(["xdotool", "windowactivate", "111"], e.runner.x_calls)
        for env in e.runner.envs:
            self.assertEqual(env["DISPLAY"], ":0")
            self.assertEqual(env["XAUTHORITY"], "/tmp/xauth_test")

    def test_focus_is_checked_between_every_key_send(self):
        e = Env(self)
        fxdev.send_command(e.ctx, "/reload")
        seq = [c[1] if c[1] != "getwindowfocus" else "focus?" for c in e.runner.x_calls]
        i = seq.index("key")
        self.assertEqual(seq[i - 1], "focus?")          # before the slash
        j = seq.index("type")
        self.assertEqual(seq[j - 1], "focus?")          # between slash and type
        k = seq.index("key", j)
        self.assertEqual(seq[k - 1], "focus?")          # before Return

    def test_not_focused_sends_nothing(self):
        e = Env(self)
        e.runner.focus = "Some Terminal"
        e.runner.activate_works = False
        with self.assertRaises(fxdev.FocusError):
            fxdev.send_command(e.ctx, "/reload")
        self.assertEqual(e.runner.sent, [])
        self.assertEqual(e.runner.executed, [])

    def test_no_window_sends_nothing(self):
        e = Env(self, windows=())
        e.runner.focus = "Some Terminal"
        with self.assertRaises(fxdev.FocusError):
            fxdev.send_command(e.ctx, "/reload")
        self.assertEqual(e.runner.sent, [])

    def test_focus_lost_after_slash_types_nothing(self):
        e = Env(self)
        e.runner.lose_after = "slash"
        with self.assertRaises(fxdev.FocusError) as cm:
            fxdev.send_command(e.ctx, "/reload")
        self.assertIn("after the slash", str(cm.exception))
        self.assertEqual(e.runner.sent, [["xdotool", "key", "slash"]])

    def test_focus_lost_while_typing_withholds_return(self):
        e = Env(self)
        e.runner.lose_after = "type"
        with self.assertRaises(fxdev.FocusError):
            fxdev.send_command(e.ctx, "/reload")
        self.assertEqual([c[1] for c in e.runner.sent], ["key", "type"])
        self.assertEqual(e.runner.executed, [])

    def test_two_windows_prefers_exact_title(self):
        e = Env(self, windows=("5", "6"))
        e.runner.names = {"5": "World of Warcraft Launcher", "6": WOW}
        res = fxdev.send_command(e.ctx, "/reload")
        self.assertEqual(res["window"], "6")

    def test_cli_exit_code_is_nonzero_and_json(self):
        e = Env(self)
        e.runner.focus = "Some Terminal"
        e.runner.activate_works = False
        code, out = e.run(["type", "/reload"])
        self.assertEqual(code, 5)
        self.assertFalse(out["ok"])
        self.assertEqual(e.runner.sent, [])


class CombatGuard(unittest.TestCase):
    def cache(self, e, age, **beacon):
        b = {"found": True, "combat": False, "group": False, "running": False, "finished": False,
             "failed": False, "errors": False, "runId8": 1}
        b.update(beacon)
        os.makedirs(e.ctx.state_dir, exist_ok=True)
        with open(os.path.join(e.ctx.state_dir, "state.json"), "w") as fh:
            json.dump({"at": e.clock.now() - age, "beacon": b, "shot": "x.png"}, fh)

    def test_combat_and_group_refuse_when_fresh(self):
        for key in ("combat", "group"):
            e = Env(self)
            self.cache(e, 30, **{key: True})
            for verb in (["type", "/reload"], ["reload"], ["selftest", "ooc"]):
                with self.subTest(key=key, verb=verb[0]):
                    code, out = e.run(verb)
                    self.assertEqual(code, 2)
                    self.assertIn(key, out["state"])
                    self.assertEqual(out["beacon_age_s"], 30.0)
            self.assertEqual(e.runner.x_calls, [])           # not even a window lookup

    def test_stale_beacon_allows(self):
        e = Env(self)
        self.cache(e, 121, combat=True)
        fxdev.send_command(e.ctx, "/reload")
        self.assertEqual(e.runner.executed, ["/reload"])

    def test_boundary_at_119_seconds_refuses(self):
        e = Env(self)
        self.cache(e, 119, group=True)
        with self.assertRaises(fxdev.Refused):
            fxdev.send_command(e.ctx, "/reload")

    def test_clear_beacon_and_no_cache_allow(self):
        e = Env(self)
        fxdev.send_command(e.ctx, "/reload")                  # no cache at all
        self.cache(e, 5)
        fxdev.send_command(e.ctx, "/reload")
        self.assertEqual(e.runner.executed, ["/reload", "/reload"])

    def test_force_overrides_and_says_so(self):
        e = Env(self)
        self.cache(e, 5, combat=True)
        code, out = e.run(["type", "/reload", "--force"])
        self.assertEqual(code, 0)
        self.assertIn("FORCED", out["guard"])

    def test_shot_is_always_allowed(self):
        e = Env(self)
        self.cache(e, 5, combat=True, group=True)
        e.runner.on_exec = lambda c: e.next_shot(combat=1, run_id=3) if c == "/fxdev shot" else None
        code, out = e.run(["shot"])
        self.assertEqual(code, 0)
        self.assertEqual(e.runner.executed, ["/fxdev shot"])
        self.assertTrue(out["beacon"]["combat"])

    def test_corrupt_state_file_is_ignored(self):
        e = Env(self)
        os.makedirs(e.ctx.state_dir, exist_ok=True)
        with open(os.path.join(e.ctx.state_dir, "state.json"), "w") as fh:
            fh.write("{not json")
        fxdev.send_command(e.ctx, "/reload")


# --------------------------------------------------------------------------
# beacon decoder
# --------------------------------------------------------------------------
class Beacon(unittest.TestCase):
    PATTERNS = [
        dict(),
        dict(combat=1, group=1, running=1, finished=1, failed=1, errors=1, run_id=255),
        dict(combat=1, run_id=0xA5),
        dict(group=1, finished=1, run_id=0x5A),
        dict(running=1, errors=1, run_id=1),
    ]

    def check(self, W, H, scale, noise=0, jpeg=0, decoys=False, patterns=None, seed=7):
        for k, p in enumerate(patterns or self.PATTERNS):
            with self.subTest(W=W, scale=scale, noise=noise, jpeg=jpeg, pattern=k):
                img = make_screen(W, H, scale=scale, noise=noise, jpeg=jpeg, decoys=decoys,
                                  seed=seed + k, **p)
                got = fxdev.decode_beacon(img)
                self.assertTrue(got["found"], got)
                want = {"combat": 0, "group": 0, "running": 0, "finished": 0, "failed": 0,
                        "errors": 0, "run_id": 0}
                want.update(p)
                self.assertEqual({n: got[n] for n in ("combat", "group", "running", "finished",
                                                      "failed", "errors")},
                                 {n: bool(want[n]) for n in ("combat", "group", "running", "finished",
                                                             "failed", "errors")})
                self.assertEqual(got["runId8"], want["run_id"])

    def test_5120x2160_scale_1(self):
        self.check(5120, 2160, 1.0)

    def test_5120x2160_scale_064(self):
        self.check(5120, 2160, 0.64)

    def test_2560x1440_scale_1(self):
        self.check(2560, 1440, 1.0)

    def test_2560x1440_scale_064(self):
        self.check(2560, 1440, 0.64)

    def test_jpeg_like_noise_5120(self):
        self.check(5120, 2160, 1.0, noise=14, jpeg=60)
        self.check(5120, 2160, 0.64, noise=14, jpeg=60, patterns=self.PATTERNS[:3])

    def test_jpeg_like_noise_2560(self):
        self.check(2560, 1440, 1.0, noise=14, jpeg=60)
        self.check(2560, 1440, 0.64, noise=14, jpeg=60, patterns=self.PATTERNS[:3])

    def test_png_noise_without_jpeg(self):
        self.check(2560, 1440, 0.64, noise=20, patterns=self.PATTERNS[:2])

    def test_decoys_do_not_fool_it(self):
        self.check(5120, 2160, 1.0, decoys=True, patterns=self.PATTERNS[:3])
        self.check(5120, 2160, 0.64, decoys=True, noise=10, jpeg=70, patterns=self.PATTERNS[:3])

    def test_all_256_run_ids_roundtrip(self):
        for rid in range(0, 256, 5):
            got = fxdev.decode_beacon(make_screen(1920, 1080, run_id=rid))
            self.assertEqual(got["runId8"], rid)
        self.assertEqual(fxdev.decode_beacon(make_screen(1920, 1080, run_id=255))["runId8"], 255)

    def test_no_beacon(self):
        for W, H in ((5120, 2160), (2560, 1440)):
            got = fxdev.decode_beacon(make_screen(W, H, beacon=False))
            self.assertEqual(got["found"], False)
            self.assertIn("reason", got)

    def test_no_beacon_with_noise_and_decoys(self):
        got = fxdev.decode_beacon(make_screen(5120, 2160, beacon=False, decoys=True, noise=14, jpeg=60))
        self.assertFalse(got["found"])

    def test_half_a_beacon_is_not_found(self):
        img = make_screen(2560, 1440, run_id=7)
        d = ImageDraw.Draw(img)
        d.rectangle([0, 0, 40, 40], fill=(10, 10, 10))        # paint the magenta cell over
        self.assertFalse(fxdev.decode_beacon(img)["found"])

    def test_coloured_middle_cells_are_a_false_match(self):
        img = make_screen(2560, 1440, run_id=7)
        d = ImageDraw.Draw(img)
        cell = 6 * 1440 / 768
        d.rectangle([round(4 * cell), 0, round(5 * cell) - 1, round(cell) - 1], fill=(200, 40, 40))
        self.assertFalse(fxdev.decode_beacon(img)["found"])

    def test_beacon_shifted_outside_the_search_region_is_not_found(self):
        img = Image.new("RGB", (2560, 1440), (20, 20, 20))
        big = make_screen(2560, 1440)
        img.paste(big.crop((0, 0, 200, 20)), (900, 600))
        self.assertFalse(fxdev.decode_beacon(img)["found"])

    def test_rgba_image_is_accepted(self):
        got = fxdev.decode_beacon(make_screen(1920, 1080, run_id=9).convert("RGBA"))
        self.assertEqual(got["runId8"], 9)


# --------------------------------------------------------------------------
# SavedVariables parsing (real luajit, temp files only)
# --------------------------------------------------------------------------
class SavedVariables(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.ctx = fxdev.Ctx(env={"FX_STATE_DIR": os.path.join(self.tmp.name, "s")})

    def sv(self, text, name="x.lua"):
        p = os.path.join(self.tmp.name, name)
        with open(p, "wb") as fh:
            fh.write(text if isinstance(text, bytes) else text.encode())
        return p

    def parse(self, text, **kw):
        return fxdev.parse_sv_file(self.ctx, self.sv(text), **kw)

    def test_real_shaped_sample(self):
        g, doc = self.parse(CORE_SV)
        db = g["ForteXorcistDB"]
        self.assertTrue(doc["ok"])
        self.assertEqual(db["version"], 1)
        self.assertEqual(db["diag"]["timerCasts"]["plain"], 2649)
        errs = db["errors"]["list"]
        self.assertIsInstance(errs, list)
        self.assertEqual([x["kind"] for x in errs], ["error", "blocked"])
        self.assertEqual(errs[0]["msg"],
                         'Forte_Timer/Rows.lua:88: attempt to index\nline two "quoted" |cffff0000red|r')
        self.assertEqual(db["cooldownLearned"], {"12345": 6.5, "67890": 30})
        self.assertEqual(db["timer"]["x"], -12.5)
        self.assertIs(db["timer"]["expand"], False)
        self.assertEqual(db["probesEvents"]["casts"], ["SECRET", 12345, 12345])
        self.assertEqual(db["probesEvents"]["restricts"], [])

    def test_dev_sample_and_run_summary(self):
        g, _ = self.parse(DEV_SV)
        s = fxdev.run_summary(g["ForteDevDB"])
        self.assertEqual((s["id"], s["pass"], s["fail"]), (6, 2, 1))
        self.assertEqual(s["failing"], [{"name": "frames", "detail": "no anchor"}])

    def test_select_path(self):
        g, _ = self.parse(CORE_SV)
        db = g["ForteXorcistDB"]
        self.assertEqual(fxdev.select_path(db, "errors.session"), 3)
        self.assertEqual(fxdev.select_path(db, "errors.list.1.kind"), "error")
        self.assertEqual(fxdev.select_path(db, "errors.list.-1.kind"), "blocked")
        self.assertEqual(fxdev.select_path(db, "cooldownLearned.12345"), 6.5)
        self.assertIs(fxdev.select_path(db, ""), db)
        for bad in ("nope", "errors.list.0", "errors.list.3", "errors.list.x", "errors.session.x", "a..b"):
            with self.assertRaises(fxdev.FxError, msg=bad):
                fxdev.select_path(db, bad)

    def test_numbers_strings_and_odd_values(self):
        g, _ = self.parse('A = { 1e300, 0.1, -0, 1/0, 0/0, "\\0\\1\\255", [true] = 1, [1.5] = 2, x = "\\"\\\\" }\n')
        a = g["A"]
        self.assertEqual(a["1"], 1e300)  # table has hash keys too, so it is an object
        self.assertEqual(a["true"], 1)
        self.assertEqual(a["1.5"], 2)
        self.assertEqual(a["x"], '"\\')
        self.assertEqual(a["4"], "<inf>")
        self.assertEqual(a["5"], "<nan>")

    def test_hostile_sample_does_not_execute(self):
        marker = os.path.join(self.tmp.name, "PWNED")
        for k, body in enumerate((
                f'os.execute("touch {marker}")',
                f'local f = io.open("{marker}", "w") f:write("x") f:close()',
                f'require("os").execute("touch {marker}")',
                f'loadstring("os.execute(\\"touch {marker}\\")")()',
                f'getfenv(0).os.execute("touch {marker}")',
                f'_G.os.execute("touch {marker}")',
                f'local s = ("x"):rep(3) io.popen("touch {marker}")',
                f'dofile("{marker}")', f'debug.sethook()')):
            with self.subTest(k=k):
                text = 'ForteXorcistDB = { a = 1 }\n' + body + '\n'
                with self.assertRaises(fxdev.FxError) as cm:
                    self.parse(text, timeout=10)
                self.assertIn("chunk error", str(cm.exception))
                self.assertFalse(os.path.exists(marker))

    def test_infinite_loop_is_cut_off(self):
        import time
        t0 = time.time()
        with self.assertRaises(fxdev.FxError) as cm:
            self.parse('ForteXorcistDB = {}\nwhile true do end\n', timeout=20)
        self.assertIn("budget", str(cm.exception))
        self.assertLess(time.time() - t0, 15)

    def test_jit_compiled_loop_is_also_cut_off(self):
        with self.assertRaises(fxdev.FxError):
            self.parse('local n = 0\nfor i = 1, 1e15 do n = n + i end\n', timeout=20)

    def test_host_timeout_path(self):
        class Hang:
            def __call__(s, argv, **kw):
                return RunResult(-9, "", "timed out", True)
        ctx = fxdev.Ctx(run=Hang(), sleep=lambda s: None, env={})
        p = self.sv("A = 1\n")
        with self.assertRaises(fxdev.TimedOut):
            fxdev.parse_sv_file(ctx, p, timeout=1)

    def test_bytecode_is_refused(self):
        with self.assertRaises(fxdev.FxError) as cm:
            self.parse(b"\x1bLJ\x02\x00garbage")
        self.assertIn("bytecode", str(cm.exception))

    def test_syntax_error_and_truncated_file(self):
        with self.assertRaises(fxdev.FxError) as cm:
            self.parse(CORE_SV[:200])
        self.assertIn("syntax", str(cm.exception))

    def test_cycles_and_depth_are_guarded(self):
        g, doc = self.parse('A = {} A.me = A A.list = { A }\n'
                            'D = ' + '{' * 60 + '1' + '}' * 60 + '\n')
        self.assertTrue(doc["truncated"])
        self.assertEqual(g["A"]["me"], "<cycle>")
        node = g["D"]
        for _ in range(100):
            if isinstance(node, list):
                node = node[0]
            else:
                break
        self.assertEqual(node, "<depth limit>")

    def test_size_limit(self):
        path = self.sv('A = { ' + ", ".join('"%s"' % ("x" * 50) for _ in range(40)) + ' }\n')
        r = fxdev.real_run(["luajit", "-", path, "500000", "40", "500"], input=fxdev.LUA_SV)
        self.assertFalse(json.loads(r.out)["ok"])
        self.assertIn("size limit", json.loads(r.out)["error"])

    def test_oversized_file_is_refused_before_luajit(self):
        calls = []
        ctx = fxdev.Ctx(run=lambda *a, **k: calls.append(a) or RunResult(0, "{}", ""), env={},
                        sleep=lambda s: None)
        p = self.sv("A = 1\n")
        old = fxdev.MAX_SV_BYTES
        fxdev.MAX_SV_BYTES = 3
        try:
            with self.assertRaises(fxdev.FxError):
                fxdev.parse_sv_file(ctx, p)
        finally:
            fxdev.MAX_SV_BYTES = old
        self.assertEqual(calls, [])

    def test_wait_stable(self):
        p = self.sv("A = 1\n")
        clock = Clock()
        ctx = fxdev.Ctx(sleep=clock.sleep, now=clock.now, env={})
        sig = fxdev.wait_stable(ctx, p, timeout=5)
        self.assertEqual(sig[1], 6)
        grow = {"n": 0}

        def writer(_c):                        # the client "keeps writing"
            grow["n"] += 1
            with open(p, "ab") as fh:
                fh.write(b"-- more\n" * grow["n"])
        clock.on_sleep = writer
        with self.assertRaises(fxdev.TimedOut):
            fxdev.wait_stable(ctx, p, timeout=3)
        with self.assertRaises(fxdev.TimedOut):
            fxdev.wait_stable(ctx, os.path.join(self.tmp.name, "missing.lua"), timeout=1)

    def test_read_sv_via_cli_path_selection(self):
        e = Env(self)
        code, out = e.run(["sv", "core", "--path", "errors.list.-1"])
        self.assertEqual(code, 0)
        self.assertEqual(out["value"]["kind"], "blocked")
        self.assertTrue(out["untrusted_data"])
        code, out = e.run(["errors"])
        self.assertEqual(code, 0)
        self.assertEqual(out["value"]["session"], 3)
        code, out = e.run(["sv", "dev"])                       # not written yet
        self.assertEqual(code, 1)
        self.assertIn("does not exist", out["error"])
        code, out = e.run(["sv", "core", "--path", "no.such"])
        self.assertEqual(code, 1)


# --------------------------------------------------------------------------
# deploy planning
# --------------------------------------------------------------------------
class Deploy(unittest.TestCase):
    def test_first_deploy_copies_only_shipped_files_and_needs_restart(self):
        e = Env(self)
        other = e.snapshot_other()
        res = fxdev.deploy(e.ctx)
        self.assertTrue(res["restart_needed"])
        self.assertTrue(res["reload_needed"])
        files = e.install_files()
        self.assertEqual({f for f in files if not f.startswith("Other_Addon/")}, {
            "Forte_Core/Forte_Core.toc", "Forte_Core/Forte_Core_Camelot.toc", "Forte_Core/Core/Init.lua",
            "Forte_Core/Fonts/x.ttf", "Forte_Core/.fx-deploy-copy",
            "Forte_Hunter/Forte_Hunter.toc", "Forte_Hunter/Forte_Hunter_Camelot.toc",
            "Forte_Hunter/Data/Hunter.lua", "Forte_Hunter/.fx-deploy-copy",
            "Forte_Dev/Forte_Dev.toc", "Forte_Dev/Forte_Dev_Camelot.toc", "Forte_Dev/Core.lua",
            "Forte_Dev/Suites/a.lua", "Forte_Dev/DevStamp.lua", "Forte_Dev/DevCommands.lua",
            "Forte_Dev/.fx-deploy-copy"})
        for bad in ("tests", "docs", ".otf", "NotForte", "Forte_NoToc", "deep.lua", ".gitignore"):
            self.assertFalse([f for f in files if bad in f], bad)
        self.assertEqual(e.snapshot_other(), other)
        self.assertEqual(sorted(os.listdir(e.addons)),
                         ["Forte_Core", "Forte_Dev", "Forte_Hunter", "Other_Addon"])
        self.assertIn("new file Forte_Core/Core/Init.lua", res["restart_reasons"])

    def test_devstamp_format_and_placeholder_not_copied(self):
        e = Env(self)
        fxdev.deploy(e.ctx)
        with open(os.path.join(e.addons, "Forte_Dev", "DevStamp.lua")) as fh:
            text = fh.read()
        m = re.fullmatch(r'ForteDevStamp = "([0-9a-f]+(?:\+dirty)?\+\d{8}T\d{6})"\n', text)
        self.assertTrue(m, text)
        want_ts = fxdev.utc_stamp_time(1_800_000_000)
        self.assertEqual(m.group(1), f"abc1234+{want_ts}")
        self.assertNotIn("PLACEHOLDER", text)

    def test_dirty_stamp_and_nogit(self):
        e = Env(self, dirty=True)
        self.assertRegex(fxdev.git_stamp(e.ctx), r"^abc1234\+dirty\+\d{8}T\d{6}$")
        e.runner.git_sha = "not a sha"
        self.assertRegex(fxdev.git_stamp(e.ctx), r"^nogit\+\d{8}T\d{6}$")

    def test_second_deploy_copies_nothing_and_needs_no_restart(self):
        e = Env(self)
        fxdev.deploy(e.ctx)
        res = fxdev.deploy(e.ctx)
        self.assertEqual(res["copied"], [])
        self.assertFalse(res["restart_needed"])
        self.assertEqual(res["new"], [])
        self.assertGreater(res["unchanged"], 5)
        self.assertTrue(res["stamp_written"])                   # the stamp is always refreshed

    def test_changed_lua_needs_reload_not_restart(self):
        e = Env(self)
        fxdev.deploy(e.ctx)
        e.write(f"{e.repo}/addon/Forte_Core/Core/Init.lua", "-- changed\n")
        res = fxdev.deploy(e.ctx)
        self.assertEqual(res["copied"], ["Forte_Core/Core/Init.lua"])
        self.assertEqual(res["changed"], ["Forte_Core/Core/Init.lua"])
        self.assertFalse(res["restart_needed"])
        self.assertTrue(res["reload_needed"])
        with open(os.path.join(e.addons, "Forte_Core", "Core", "Init.lua")) as fh:
            self.assertEqual(fh.read(), "-- changed\n")

    def test_changed_toc_needs_restart(self):
        e = Env(self)
        fxdev.deploy(e.ctx)
        for t in ("Forte_Hunter.toc", "Forte_Hunter_Camelot.toc"):
            e.write(f"{e.repo}/addon/Forte_Hunter/{t}", "## Interface: 16001\nData/Hunter.lua\nData/Two.lua\n")
        res = fxdev.deploy(e.ctx)
        self.assertTrue(res["restart_needed"])
        self.assertEqual(sorted(res["toc_changed"]),
                         ["Forte_Hunter/Forte_Hunter.toc", "Forte_Hunter/Forte_Hunter_Camelot.toc"])
        self.assertTrue(any("toc changed" in r for r in res["restart_reasons"]))

    def test_new_lua_file_needs_restart(self):
        e = Env(self)
        fxdev.deploy(e.ctx)
        e.write(f"{e.repo}/dev/Forte_Dev/Suites/b.lua", "-- new suite\n")
        res = fxdev.deploy(e.ctx)
        self.assertTrue(res["restart_needed"])
        self.assertEqual(res["new"], ["Forte_Dev/Suites/b.lua"])

    def test_missing_generated_files_count_as_new(self):
        e = Env(self)
        fxdev.deploy(e.ctx)
        os.unlink(os.path.join(e.addons, "Forte_Dev", "DevCommands.lua"))
        res = fxdev.deploy(e.ctx)
        self.assertTrue(res["restart_needed"])
        self.assertEqual(res["new"], ["Forte_Dev/DevCommands.lua"])

    def test_existing_devcommands_is_never_overwritten_by_deploy(self):
        e = Env(self)
        fxdev.deploy(e.ctx)
        p = os.path.join(e.addons, "Forte_Dev", "DevCommands.lua")
        e.write(p, 'ForteDevCommands = { "shot" }\n')
        fxdev.deploy(e.ctx)
        with open(p) as fh:
            self.assertEqual(fh.read(), 'ForteDevCommands = { "shot" }\n')

    def test_extra_install_files_are_reported_not_deleted(self):
        e = Env(self)
        fxdev.deploy(e.ctx)
        extra = os.path.join(e.addons, "Forte_Core", "Core", "Old.lua")
        e.write(extra, "stale\n")
        res = fxdev.deploy(e.ctx)
        self.assertTrue(os.path.exists(extra))
        self.assertIn("Forte_Core/Core/Old.lua", res["extra_in_install"])
        self.assertFalse(res["restart_needed"])

    def test_dry_run_writes_nothing(self):
        e = Env(self)
        before = e.install_files()
        res = fxdev.deploy(e.ctx, dry_run=True)
        self.assertTrue(res["dry_run"])
        self.assertTrue(res["restart_needed"])
        self.assertIn("Forte_Core/Core/Init.lua", res["would_copy"])
        self.assertEqual(e.install_files(), before)

    def test_missing_addons_dir_is_never_created(self):
        e = Env(self)
        os.rename(e.addons, e.addons + ".gone")
        with self.assertRaises(fxdev.FxError):
            fxdev.deploy(e.ctx)
        self.assertFalse(os.path.exists(e.addons))

    def test_symlinked_install_dir_is_never_written_through(self):
        e = Env(self)
        target = os.path.join(e.repo, "addon", "Forte_Hunter")
        os.symlink(target, os.path.join(e.addons, "Forte_Hunter"))
        with open(os.path.join(target, "Data", "Hunter.lua"), "rb") as fh:
            repo_before = fh.read()
        res = fxdev.deploy(e.ctx)
        self.assertTrue(any(s.get("addon") == "Forte_Hunter" for s in res["skipped"]))
        self.assertIn("already live", json.dumps(res["skipped"]))
        with open(os.path.join(target, "Data", "Hunter.lua"), "rb") as fh:
            self.assertEqual(fh.read(), repo_before)
        self.assertTrue(os.path.islink(os.path.join(e.addons, "Forte_Hunter")))
        self.assertTrue(os.path.exists(os.path.join(e.addons, "Forte_Core", "Core", "Init.lua")))

    def test_symlink_to_foreign_dir_is_refused(self):
        e = Env(self)
        foreign = os.path.join(e.tmp.name, "foreign")
        os.makedirs(foreign)
        os.symlink(foreign, os.path.join(e.addons, "Forte_Core"))
        res = fxdev.deploy(e.ctx)
        self.assertEqual(os.listdir(foreign), [])
        self.assertIn("refusing to write through it", json.dumps(res["skipped"]))

    def test_symlinked_subdir_cannot_escape_the_addon_folder(self):
        e = Env(self)
        fxdev.deploy(e.ctx)
        outside = os.path.join(e.tmp.name, "outside")
        os.makedirs(outside)
        import shutil
        shutil.rmtree(os.path.join(e.addons, "Forte_Core", "Core"))
        os.symlink(outside, os.path.join(e.addons, "Forte_Core", "Core"))
        e.write(f"{e.repo}/addon/Forte_Core/Core/Init.lua", "-- changed\n")
        res = fxdev.deploy(e.ctx)
        self.assertEqual(os.listdir(outside), [])
        self.assertTrue(any("escapes" in s.get("reason", "") for s in res["skipped"]))

    def test_no_dev_dir_in_repo(self):
        e = Env(self, with_dev=False)
        res = fxdev.deploy(e.ctx)
        self.assertIn("warning", res)
        self.assertFalse(os.path.exists(os.path.join(e.addons, "Forte_Dev")))

    def test_marker_not_added_to_existing_dirs(self):
        e = Env(self)
        e.write(os.path.join(e.addons, "Forte_Hunter", "Data", "Hunter.lua"), "old\n")
        fxdev.deploy(e.ctx)
        self.assertFalse(os.path.exists(os.path.join(e.addons, "Forte_Hunter", ".fx-deploy-copy")))

    def test_cli_deploy_dry_run_json(self):
        e = Env(self)
        code, out = e.run(["deploy", "--dry-run"])
        self.assertEqual(code, 0)
        self.assertTrue(out["restart_needed"])
        self.assertEqual(e.install_files(), {"Other_Addon/data.lua"})


# --------------------------------------------------------------------------
# DevCommands quoting
# --------------------------------------------------------------------------
class DevCommands(unittest.TestCase):
    NASTY = ['plain', 'with "double" quotes', "with 'single' quotes", "back\\slash", "new\nline\r\n",
             "tab\there", "nul\x00byte", "ctrl\x01\x1f\x7f", "caf\u00e9 \u2603 \U0001f600", "]] [[ --[==[ ]==]",
             "digits after escape \x01234", "trailing backslash\\", '", } print("pwned") --', ""]

    def parse(self, e, text):
        p = os.path.join(e.tmp.name, "DevCommands.lua")
        e.write(p, text)
        g, _ = fxdev.parse_sv_file(e.ctx, p, timeout=10)
        return g["ForteDevCommands"]

    def test_quoting_round_trips_through_luajit(self):
        e = Env(self)
        for s in self.NASTY:
            with self.subTest(s=repr(s)):
                lit = fxdev.lua_quote(s)
                self.assertNotIn("\n", lit)
                self.assertTrue(lit.isascii())
                got = self.parse(e, f"ForteDevCommands = {{ {lit} }}\n")
                self.assertEqual(got[0], s)

    def test_render_mixed_entries_round_trip(self):
        e = Env(self)
        entries = [("verb", "selftest ooc"), ("lua", 'print("a\\nb")\nprint(\'c\')'), ("verb", "shot")]
        got = self.parse(e, fxdev.render_devcommands(entries, "t"))
        self.assertEqual(got, ["selftest ooc", {"lua": 'print("a\\nb")\nprint(\'c\')'}, "shot"])
        self.assertEqual(self.parse(e, fxdev.render_devcommands([])), [])

    def test_cli_writes_file_in_order(self):
        e = Env(self)
        fxdev.deploy(e.ctx)
        code, out = e.run(["commands", "selftest ooc", "--lua", "print(1)", "shot", "--lua=print(2)"])
        self.assertEqual(code, 0, out)
        self.assertFalse(out["new_file"])
        self.assertFalse(out["restart_needed"])
        got = self.parse(e, open(os.path.join(e.addons, "Forte_Dev", "DevCommands.lua")).read())
        self.assertEqual(got, ["selftest ooc", {"lua": "print(1)"}, "shot", {"lua": "print(2)"}])

    def test_cli_no_args_clears(self):
        e = Env(self)
        fxdev.deploy(e.ctx)
        e.run(["commands", "shot"])
        code, out = e.run(["commands"])
        self.assertEqual(code, 0)
        self.assertEqual(self.parse(e, open(os.path.join(e.addons, "Forte_Dev", "DevCommands.lua")).read()), [])

    def test_refusals(self):
        e = Env(self)
        fxdev.deploy(e.ctx)
        for args in (["commands", "--lua", "SendChatMessage('x','SAY')"], ["commands", "/reload"],
                     ["commands", "--lua"], ["commands", "--bogus"], ["commands", "a\nb"],
                     ["commands", "--lua", "x" * 2001], ["commands", "--lua", "_G.Quit()"],
                     ["commands", "x" * 241]):
            with self.subTest(args=args[:3]):
                code, out = e.run(args)
                self.assertEqual(code, 2, out)
        code, out = e.run(["commands", "--lua", "Quit()", "--allow-unsafe"])
        self.assertEqual(code, 0)

    def test_without_forte_dev_installed(self):
        e = Env(self)
        code, out = e.run(["commands", "shot"])
        self.assertEqual(code, 1)
        self.assertIn("fxdev.py deploy", out["error"])

    def test_missing_file_is_flagged_as_restart_needed(self):
        e = Env(self)
        fxdev.deploy(e.ctx)
        os.unlink(os.path.join(e.addons, "Forte_Dev", "DevCommands.lua"))
        code, out = e.run(["commands", "shot"])
        self.assertTrue(out["new_file"])
        self.assertTrue(out["restart_needed"])

    def test_symlinked_devcommands_is_refused(self):
        e = Env(self)
        fxdev.deploy(e.ctx)
        p = os.path.join(e.addons, "Forte_Dev", "DevCommands.lua")
        victim = os.path.join(e.tmp.name, "victim.txt")
        e.write(victim, "precious")
        os.unlink(p)
        os.symlink(victim, p)
        code, _ = e.run(["commands", "shot"])
        self.assertEqual(code, 1)
        self.assertEqual(open(victim).read(), "precious")


# --------------------------------------------------------------------------
# verbs end-to-end against the fakes
# --------------------------------------------------------------------------
class Verbs(unittest.TestCase):
    def shot_hook(self, e, queue):
        def on_exec(cmd):
            if cmd == "/fxdev shot":
                e.next_shot(**(queue.pop(0) if len(queue) > 1 else queue[0]))
        e.runner.on_exec = on_exec

    def test_shot_decodes_writes_crops_and_caches_state(self):
        e = Env(self)
        self.shot_hook(e, [dict(size=(2560, 1440), run_id=42, finished=1)])
        code, out = e.run(["shot"])
        self.assertEqual(code, 0, out)
        self.assertTrue(out["beacon"]["found"])
        self.assertEqual(out["beacon"]["runId8"], 42)
        self.assertTrue(out["beacon"]["finished"])
        self.assertEqual(set(out["crops"]), {"panel", "chat", "overview"})
        sizes = {k: Image.open(v).size for k, v in out["crops"].items()}
        self.assertEqual(sizes["panel"], (int(2560 * 0.30), int(1440 * 0.45)))
        self.assertEqual(sizes["chat"], (int(2560 * 0.24), 1440 - int(1440 * 0.72)))
        self.assertEqual(sizes["overview"][0], 1600)
        self.assertTrue(out["crops"]["panel"].startswith(e.ctx.state_dir))
        st = fxdev.load_state(e.ctx)
        self.assertEqual(st["beacon"]["runId8"], 42)
        self.assertEqual(e.runner.executed, ["/fxdev shot"])

    def test_shot_without_beacon_warns(self):
        e = Env(self)
        self.shot_hook(e, [dict(beacon=False)])
        code, out = e.run(["shot"])
        self.assertEqual(code, 0)
        self.assertFalse(out["beacon"]["found"])
        self.assertIn("warning", out)

    def test_shot_waits_for_stable_size_and_ignores_old_files(self):
        e = Env(self)
        e.next_shot(run_id=1)                                   # an old shot already on disk
        calls = {"n": 0}

        def on_exec(cmd):
            e.pending_png = os.path.join(e.shots, "WoWScrnShot_111226_999999.png")
            data = png_bytes(make_screen(1920, 1080, run_id=77))
            with open(e.pending_png, "wb") as fh:             # first only half the bytes
                fh.write(data[:len(data) // 2])
            e.full = data

        def on_sleep(_c):
            if not hasattr(e, "pending_png"):         # the command has not been executed yet
                return
            calls["n"] += 1
            if calls["n"] == 3:
                with open(e.pending_png, "wb") as fh:
                    fh.write(e.full)
        e.runner.on_exec = on_exec
        e.clock.on_sleep = on_sleep
        code, out = e.run(["shot"])
        self.assertEqual(code, 0, out)
        self.assertEqual(out["beacon"]["runId8"], 77)

    def test_shot_timeout_and_non_png_hint(self):
        e = Env(self)
        code, out = e.run(["shot", "--timeout", "3"])
        self.assertEqual(code, 3)
        e2 = Env(self)
        def jpg(_c):
            with open(os.path.join(e2.shots, "WoWScrnShot_1.jpg"), "wb") as fh:
                fh.write(b"x")
        e2.runner.on_exec = jpg
        code, out = e2.run(["shot", "--timeout", "3"])
        self.assertEqual(code, 3)
        self.assertIn("screenshotFormat png", out["error"])

    def test_shot_file_mode_types_nothing_and_keeps_cache(self):
        e = Env(self)
        p = os.path.join(e.tmp.name, "x.png")
        make_screen(1920, 1080, combat=1, run_id=3).save(p)
        code, out = e.run(["shot", "--file", p])
        self.assertEqual(code, 0)
        self.assertTrue(out["beacon"]["combat"])
        self.assertEqual(e.runner.x_calls, [])
        self.assertEqual(fxdev.load_state(e.ctx), {})
        self.assertEqual(e.run(["shot", "--file", p + ".nope"])[0], 1)

    def test_reload_waits_for_sv_mtime_change(self):
        e = Env(self)
        core = os.path.join(e.acct, "Forte_Core.lua")
        e.runner.on_exec = lambda c: e.bump(core, CORE_SV + "-- again\n")
        code, out = e.run(["reload"])
        self.assertEqual(code, 0, out)
        self.assertEqual(e.runner.executed, ["/reload"])
        self.assertEqual(out["changed"], ["Forte_Core.lua"])
        self.assertIn(4.0, e.clock.sleeps)                      # the settle

    def test_reload_times_out_when_nothing_is_written(self):
        e = Env(self)
        code, out = e.run(["reload", "--timeout", "3"])
        self.assertEqual(code, 3)
        self.assertEqual(e.runner.executed, ["/reload"])

    def test_reload_refuses_in_combat_and_without_account(self):
        e = Env(self)
        fxdev.save_state(e.ctx, {"found": True, "combat": True, "group": False}, "x")
        self.assertEqual(e.run(["reload"])[0], 2)
        e2 = Env(self)
        os.unlink(os.path.join(e2.acct, "Forte_Core.lua"))
        self.assertEqual(e2.run(["reload"])[0], 1)
        self.assertEqual(e2.runner.x_calls, [])

    def test_selftest_happy_path(self):
        e = Env(self)
        self.shot_hook(e, [dict(run_id=5, finished=1),               # baseline
                           dict(run_id=6, running=1, finished=1),    # running (old finished bit still set)
                           dict(run_id=6, finished=1, errors=1)])    # done
        code, out = e.run(["selftest", "ooc"])
        self.assertEqual(code, 0, out)
        self.assertEqual(e.runner.executed,
                         ["/fxdev shot", "/fxdev selftest ooc", "/fxdev shot", "/fxdev shot"])
        self.assertEqual(out["runId8_before"], 5)
        self.assertEqual(out["beacon"]["runId8"], 6)
        self.assertEqual(out["polls"], 2)
        self.assertTrue(out["finished"])
        self.assertTrue(out["passed"])
        self.assertIn("reload", out["note"])
        self.assertGreaterEqual(e.clock.sleeps.count(4.0), 2)

    def test_selftest_uses_fresh_cache_instead_of_baseline_shot(self):
        e = Env(self)
        fxdev.save_state(e.ctx, {"found": True, "combat": False, "group": False, "runId8": 9}, "x")
        self.shot_hook(e, [dict(run_id=10, finished=1)])
        code, out = e.run(["selftest"])
        self.assertEqual(code, 0, out)
        self.assertEqual(e.runner.executed, ["/fxdev selftest", "/fxdev shot"])
        self.assertEqual(out["runId8_before"], 9)

    def test_selftest_refuses_when_baseline_shows_combat(self):
        e = Env(self)
        self.shot_hook(e, [dict(run_id=5, combat=1)])
        code, out = e.run(["selftest", "ooc"])
        self.assertEqual(code, 2)
        self.assertEqual(e.runner.executed, ["/fxdev shot"])

    def test_selftest_times_out_with_last_beacon(self):
        e = Env(self)
        self.shot_hook(e, [dict(run_id=5), dict(run_id=6, running=1)])
        code, out = e.run(["selftest", "--timeout", "10"])
        self.assertEqual(code, 3)
        self.assertTrue(out["beacon"]["running"])
        self.assertIn("polls", out)

    def test_selftest_does_not_accept_a_stale_finished_run(self):
        e = Env(self)
        self.shot_hook(e, [dict(run_id=5, finished=1)])            # never changes
        code, out = e.run(["selftest", "--timeout", "10"])
        self.assertEqual(code, 3)

    def test_selftest_suite_name_is_validated(self):
        e = Env(self)
        code, out = e.run(["selftest", "a b; /quit"])
        self.assertEqual(code, 2)
        self.assertEqual(e.runner.calls, [])

    def test_status_reports_without_sending_input(self):
        e = Env(self)
        e.next_shot(run_id=1)
        code, out = e.run(["status"])
        self.assertEqual(code, 0, out)
        self.assertTrue(out["game_running"])
        self.assertEqual(out["game_pid"], 123)
        self.assertEqual(out["window_id"], "111")
        self.assertEqual(out["account"], "ACC#1")
        self.assertFalse(out["install"]["in_sync"])
        self.assertIn("Forte_Core/Core/Init.lua", out["install"]["missing_in_install"])
        self.assertTrue(out["sv"]["core"]["exists"])
        self.assertFalse(out["sv"]["dev"]["exists"])
        self.assertTrue(out["newest_screenshot"]["path"].endswith(".png"))
        self.assertEqual(e.runner.sent, [])
        fxdev.deploy(e.ctx)
        e.write(os.path.join(e.acct, "Forte_Dev.lua"), DEV_SV.replace("STAMP", "zzz"))
        code, out = e.run(["status"])
        self.assertTrue(out["install"]["in_sync"])
        self.assertEqual(out["dev_stamp"]["last_run"], "zzz")
        self.assertFalse(out["dev_stamp"]["match"])

    def test_status_game_not_running_and_lookalike_appid(self):
        e = Env(self, game_running=False)
        os.makedirs(os.path.join(e.proc, "77"))
        with open(os.path.join(e.proc, "77", "cmdline"), "wb") as fh:
            fh.write(b"x\0AppId=26911801731\0")
        self.assertIsNone(fxdev.game_pid(e.ctx))

    def test_account_discovery(self):
        e = Env(self)
        self.assertEqual(e.ctx.account(), "ACC#1")
        e.write(os.path.join(e.wow, "WTF", "Account", "OTHER", "SavedVariables", "Forte_Core.lua"), "")
        with self.assertRaises(fxdev.FxError):
            e.ctx.account()
        e.ctx.env["FX_WOW_ACCOUNT"] = "OTHER"
        self.assertEqual(e.ctx.account(), "OTHER")
        e.ctx.env["FX_WOW_ACCOUNT"] = "../x"
        with self.assertRaises(fxdev.FxError):
            e.ctx.account()

    def test_loop_stops_for_restart_before_any_input(self):
        e = Env(self)
        code, out = e.run(["loop"])
        self.assertEqual(code, 4)
        self.assertEqual(e.runner.sent, [])
        self.assertTrue(out["steps"]["deploy"]["restart_needed"])

    def test_loop_refuses_when_game_not_running(self):
        e = Env(self, game_running=False)
        code, out = e.run(["loop"])
        self.assertEqual(code, 1)
        self.assertEqual(e.install_files(), {"Other_Addon/data.lua"})

    def test_loop_one_iteration_end_to_end(self):
        e = Env(self)
        fxdev.deploy(e.ctx)                                       # first install (owner restarts)
        e.runner.calls.clear()
        e.runner.executed.clear()
        core = os.path.join(e.acct, "Forte_Core.lua")
        dev = os.path.join(e.acct, "Forte_Dev.lua")
        shots = [dict(run_id=5), dict(run_id=6, running=1), dict(run_id=6, finished=1)]
        reloads = {"n": 0}

        def on_exec(cmd):
            if cmd == "/fxdev shot":
                e.next_shot(**(shots.pop(0) if len(shots) > 1 else shots[0]))
            elif cmd == "/reload":
                reloads["n"] += 1
                e.bump(core, CORE_SV + f"-- r{reloads['n']}\n")
                with open(os.path.join(e.addons, "Forte_Dev", "DevStamp.lua")) as fh:
                    stamp = re.search(r'"([^"]+)"', fh.read()).group(1)
                e.bump(dev, DEV_SV.replace("STAMP", stamp))
        e.runner.on_exec = on_exec
        code, out = e.run(["loop", "--suite", "ooc"])
        self.assertEqual(code, 0, out)
        self.assertEqual(e.runner.executed,
                         ["/reload", "/fxdev shot", "/fxdev selftest ooc", "/fxdev shot", "/fxdev shot",
                          "/fxdev shot", "/reload"])
        self.assertEqual(e.runner.executed[0], "/reload")
        self.assertEqual(e.runner.executed[-1], "/reload")
        self.assertIn("/fxdev selftest ooc", e.runner.executed)
        self.assertEqual(reloads["n"], 2)
        self.assertTrue(out["ok"])
        self.assertTrue(out["stamp_match"])
        self.assertEqual((out["run"]["pass"], out["run"]["fail"]), (2, 1))
        self.assertEqual(out["run"]["failing"][0]["name"], "frames")
        self.assertEqual(out["errors"]["session"], 3)
        self.assertEqual(list(out["steps"]), ["deploy", "reload1", "selftest", "shot", "reload2", "read_dev"])

    def test_loop_is_one_iteration_only(self):
        e = Env(self)
        fxdev.deploy(e.ctx)
        e.runner.executed.clear()
        # nothing ever changes the SV files -> the first reload times out and the loop stops
        code, out = e.run(["loop", "--timeout", "3"])
        self.assertEqual(code, 3)
        self.assertEqual(out["failed_step"], "reload1")
        self.assertEqual(e.runner.executed, ["/reload"])

    def test_cli_usage_errors(self):
        import contextlib
        e = Env(self)
        for argv in ([], ["bogus"], ["sv"], ["sv", "x"], ["type"]):
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(fxdev.main(argv, ctx=e.ctx, out=io.StringIO()), 2, argv)
        self.assertEqual(e.runner.calls, [])
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(fxdev.main(["--help"], ctx=e.ctx, out=io.StringIO()), 0)


class Plumbing(unittest.TestCase):
    def test_real_run_never_raises(self):
        r = fxdev.real_run(["definitely-not-a-binary-xyz"])
        self.assertEqual(r.rc, 127)
        r = fxdev.real_run(["sleep", "5"], timeout=0.2)
        self.assertTrue(r.timed_out)

    def test_default_game_dir_and_override(self):
        c = fxdev.Ctx(env={})
        self.assertTrue(c.wow_dir.endswith("compatdata/2691180173/pfx/drive_c/Program Files (x86)/"
                                           "World of Warcraft/_forever_"))
        self.assertEqual(fxdev.Ctx(env={"FX_WOW_DIR": "/x"}).addons_dir, "/x/Interface/AddOns")

    def test_xauthority_glob(self):
        with tempfile.TemporaryDirectory() as d:
            c = fxdev.Ctx(env={}, run_dir=d)
            with self.assertRaises(fxdev.FocusError):
                fxdev.x_env(c)
            open(os.path.join(d, "xauth_AbC"), "w").close()
            self.assertEqual(fxdev.x_env(c)["XAUTHORITY"], os.path.join(d, "xauth_AbC"))
            self.assertEqual(fxdev.x_env(c)["DISPLAY"], ":0")

    def test_state_dir_must_be_ours(self):
        with tempfile.TemporaryDirectory() as d:
            target = os.path.join(d, "real")
            os.makedirs(target)
            link = os.path.join(d, "link")
            os.symlink(target, link)
            with self.assertRaises(fxdev.FxError):
                fxdev.Ctx(env={}, state_dir=link).ensure_state_dir()

    def test_lua_script_has_no_forbidden_host_calls(self):
        # the SV script must read the file, never run anything else
        for bad in ("os.execute", "io.popen", "require(", "dofile", "loadfile"):
            self.assertNotIn(bad, fxdev.LUA_SV)


if __name__ == "__main__":
    unittest.main(verbosity=1)
