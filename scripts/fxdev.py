#!/usr/bin/env python3
"""fxdev.py - host side of the in-game dev loop (PLAN section 11.11, slice Q3).

    scripts/fxdev.py status
    scripts/fxdev.py deploy [--dry-run]
    scripts/fxdev.py commands [VERB ...] [--lua 'code' ...]
    scripts/fxdev.py type "<cmd>" [--force] [--allow-unsafe]
    scripts/fxdev.py reload [--force] [--timeout S] [--settle S]
    scripts/fxdev.py shot [--timeout S] [--file PNG]
    scripts/fxdev.py sv core|dev [--path a.b.c]
    scripts/fxdev.py errors
    scripts/fxdev.py selftest [suite] [--force] [--timeout S] [--poll S]
    scripts/fxdev.py loop [--suite S] [--force]

Stdlib + PIL + the `luajit` and `xdotool` binaries. Every verb prints ONE JSON
document on stdout. Exit codes: 0 ok, 1 error, 2 refused by a safety rule (or
usage), 3 timeout, 4 owner action needed (client restart), 5 window/focus.

The tool types into the owner's running game window, so every send passes the
same gates (docs/dev-loop.md): a whitelist of slash commands, a deny-list for
`/run` payloads, an X focus guard before every key send, a combat/group guard
from the last decoded beacon, one command at a time, bounded waits. It never
runs unattended loops. SavedVariables are parsed by luajit inside an EMPTY
environment; game-written data is never executed in a real one.

All side effects (subprocesses, clock, sleeping, paths) go through `Ctx`, so
test_fxdev.py drives everything with fakes and never touches xdotool or the
real install.
"""
import argparse
import datetime
import glob
import io
import json
import os
import re
import stat
import subprocess
import sys
import time
from collections import namedtuple

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APPID = "2691180173"
WINDOW_NAME = "World of Warcraft"
DEFAULT_STATE_DIR = "/tmp/fxdev"
MAX_CMD_LEN = 240
GUARD_MAX_AGE = 120.0           # seconds a beacon reading blocks typing
MAX_SV_BYTES = 64 * 1024 * 1024
MAX_LUA_CODE = 2000
MARKER = ".fx-deploy-copy"      # same marker scripts/deploy.sh --copy writes

# addon trees: (name pattern, excluded dir parts, excluded suffixes)
ADDON_EXCLUDE_DIRS = ("tests", "docs")       # same as scripts/release.py
ADDON_EXCLUDE_SUFFIXES = (".otf",)
DEV_EXCLUDE_DIRS = ("tests",)
GENERATED = ("DevStamp.lua", "DevCommands.lua")   # written by this tool, never copied

SV_FILES = {"core": ("Forte_Core.lua", "ForteXorcistDB"),
            "dev": ("Forte_Dev.lua", "ForteDevDB")}


# --------------------------------------------------------------------------
# errors, process plumbing, context
# --------------------------------------------------------------------------
class FxError(Exception):
    code = 1

    def __init__(self, msg, **extra):
        super().__init__(msg)
        self.extra = extra


class Refused(FxError):
    code = 2


class TimedOut(FxError):
    code = 3


class OwnerAction(FxError):
    code = 4


class FocusError(FxError):
    code = 5


RunResult = namedtuple("RunResult", "rc out err timed_out", defaults=(False,))


def real_run(argv, env=None, timeout=None, input=None, limits=None):
    """Run a subprocess; never raises for rc/timeout/missing binary."""
    pre = None
    if limits:
        def pre():
            import resource
            if "cpu" in limits:
                resource.setrlimit(resource.RLIMIT_CPU, (limits["cpu"], limits["cpu"]))
            if "as" in limits:
                resource.setrlimit(resource.RLIMIT_AS, (limits["as"], limits["as"]))
    data = input.encode() if isinstance(input, str) else input
    try:
        p = subprocess.run(argv, env=env, input=data, capture_output=True,
                           timeout=timeout, preexec_fn=pre)
    except subprocess.TimeoutExpired:
        return RunResult(-9, "", "timed out", True)
    except OSError as e:
        return RunResult(127, "", str(e))
    return RunResult(p.returncode, p.stdout.decode("utf-8", "replace"),
                     p.stderr.decode("utf-8", "replace"))


class Ctx:
    """Everything that touches the outside world, injectable for tests."""

    def __init__(self, env=None, run=None, sleep=None, now=None, root=ROOT,
                 state_dir=None, proc_root="/proc", uid=None, run_dir=None):
        self.env = dict(os.environ if env is None else env)
        self.run = run or real_run
        self.sleep = sleep or time.sleep
        self.now = now or time.time
        self.root = root
        self.uid = os.getuid() if uid is None else uid
        self.state_dir = state_dir or self.env.get("FX_STATE_DIR") or DEFAULT_STATE_DIR
        self.proc_root = proc_root
        self.run_dir = run_dir or f"/run/user/{self.uid}"

    # --- paths ---
    @property
    def wow_dir(self):
        d = self.env.get("FX_WOW_DIR")
        if d:
            return d
        return os.path.join(os.path.expanduser("~"), ".steam", "steam", "steamapps",
                            "compatdata", APPID, "pfx", "drive_c", "Program Files (x86)",
                            "World of Warcraft", "_forever_")

    @property
    def addons_dir(self):
        return os.path.join(self.wow_dir, "Interface", "AddOns")

    @property
    def shots_dir(self):
        return os.path.join(self.wow_dir, "Screenshots")

    def account(self):
        root = os.path.join(self.wow_dir, "WTF", "Account")
        forced = self.env.get("FX_WOW_ACCOUNT")
        if forced:
            if "/" in forced or forced in (".", ".."):
                raise FxError(f"FX_WOW_ACCOUNT {forced!r} is not a plain folder name")
            if not os.path.isdir(os.path.join(root, forced)):
                raise FxError(f"FX_WOW_ACCOUNT folder not found: {os.path.join(root, forced)}")
            return forced
        try:
            names = sorted(os.listdir(root))
        except OSError as e:
            raise FxError(f"cannot list {root}: {e}")
        cands = [n for n in names
                 if os.path.isfile(os.path.join(root, n, "SavedVariables", "Forte_Core.lua"))]
        if len(cands) == 1:
            return cands[0]
        if not cands:
            raise FxError(f"no account folder under {root} has SavedVariables/Forte_Core.lua "
                          "(set FX_WOW_ACCOUNT)")
        raise FxError(f"several account folders have Forte_Core.lua: {cands} (set FX_WOW_ACCOUNT)")

    def sv_path(self, which):
        return os.path.join(self.wow_dir, "WTF", "Account", self.account(),
                            "SavedVariables", SV_FILES[which][0])

    def ensure_state_dir(self):
        d = self.state_dir
        try:
            os.makedirs(d, mode=0o700, exist_ok=True)
            st = os.lstat(d)
        except OSError as e:
            raise FxError(f"cannot use state dir {d}: {e}")
        if not stat.S_ISDIR(st.st_mode) or st.st_uid != self.uid:
            raise FxError(f"state dir {d} is not a directory owned by this user")
        return d


def utc_stamp_time(epoch):
    return datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc).strftime("%Y%m%dT%H%M%S")


def iso(epoch):
    return datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def atomic_write(path, data):
    """Write bytes/str next to `path`, then rename (the client never sees half a file)."""
    if isinstance(data, str):
        data = data.encode("utf-8")
    tmp = f"{path}.fxtmp{os.getpid()}"
    try:
        with open(tmp, "wb") as fh:
            fh.write(data)
        os.replace(tmp, path)
    finally:
        if os.path.lexists(tmp):
            os.unlink(tmp)


# --------------------------------------------------------------------------
# typed-command safety: whitelist + /run deny-list
# --------------------------------------------------------------------------
_WHITELIST = (
    ("reload", re.compile(r"^/reload(?: .*)?$")),
    ("fx", re.compile(r"^/fx(?: .*)?$")),
    ("fxdev", re.compile(r"^/fxdev(?: .*)?$")),
    ("run", re.compile(r"^/run .*\S.*$")),
    ("console-screenshotFormat", re.compile(r"^/console screenshotFormat [A-Za-z0-9]{1,8}$")),
    ("chatlog", re.compile(r"^/chatlog(?: .*)?$")),
    ("combatlog", re.compile(r"^/combatlog(?: .*)?$")),
)

# Exact API names (matched as whole identifiers, case-insensitive)...
DENY_EXACT = (
    # chat / communication
    "SendChatMessage", "SendAddonMessage", "SendAddonMessageLogged", "SendMail",
    "BNSendWhisper", "BNSendFriendInvite", "BNSendConversationMessage", "SendSystemMessage",
    "DoEmote", "JoinChannelByName", "LeaveChannelByName", "ChatFrame_OpenChat",
    # casting / using / targeting / interaction
    "UseAction", "UseItemByName", "UseContainerItem", "UseInventoryItem", "UseToy",
    "TargetUnit", "TargetByName", "AssistUnit", "FocusUnit", "InteractUnit", "SetRaidTarget",
    "RunMacro", "RunMacroText", "RunBinding", "SpellTargetUnit", "SpellStopTargeting",
    "CameraOrSelectOrMove", "TurnOrAction", "ToggleAutoRun", "StartAutoRun", "StopAutoRun",
    "JumpOrAscendStart", "JumpOrAscend", "AscendStop", "SitStandOrDescendStart", "DescendStop",
    "StartAttack", "AttackTarget", "PetAttack", "PetPassiveMode",
    # group / guild / social
    "InviteUnit", "UninviteUnit", "LeaveParty", "ConvertToRaid", "ConvertToParty",
    "PromoteToLeader", "AcceptGroup", "DeclineGroup", "GuildInvite", "GuildUninvite",
    "GuildPromote", "GuildDemote", "GuildLeave", "GuildDisband", "GuildSetMOTD",
    "AddFriend", "AddOrRemoveFriend", "AddIgnore", "AddOrDelIgnore",
    # trade / economy / items
    "AcceptTrade", "InitiateTrade", "CancelTrade", "SetTradeMoney", "AddTradeMoney",
    "BuyMerchantItem", "BuybackItem", "SellCursorItem", "DeleteCursorItem",
    "BuyGuildBankTab", "DepositGuildBankMoney", "WithdrawGuildBankMoney",
    "TakeInboxItem", "TakeInboxMoney", "DeleteInboxItem", "AutoLootMailItem",
    "LootSlot", "ConfirmLootSlot", "EquipItemByName", "EquipCursorItem", "AutoEquipCursorItem",
    "SplitContainerItem", "DestroyItem", "AcceptQuest", "CompleteQuest", "GetQuestReward",
    "AbandonQuest", "StartDuel", "CancelDuel", "AcceptDuel", "AcceptBattlefieldPort",
    "JoinBattlefield", "RepopMe", "AcceptResurrect", "ReleaseCorpse", "ResurrectPlayer",
    # session / account
    "Logout", "Quit", "ForceQuit", "CancelLogout", "Camp",
    "SetBinding", "SetBindingClick", "SetBindingSpell", "SetBindingItem", "SetBindingMacro",
    "SaveBindings", "LoadBindings",
    # dynamic code / evasion helpers
    "_G", "_ENV", "getfenv", "setfenv", "getglobal", "setglobal", "loadstring", "load",
    "loadfile", "dofile", "RunScript", "securecall", "securecallfunction", "forceinsecure",
    "rawget", "rawset", "debug",
)
# ...and API families (the name plus any suffix: CastSpellByName, PickupItem, MoveForwardStart).
DENY_PREFIX = (
    "C_ChatInfo.Send", "C_Club.Send", "C_Club.Create", "C_Club.Invite",
    "C_PartyInfo.Invite", "C_PartyInfo.Leave", "C_PartyInfo.Confirm", "C_PartyInfo.Convert",
    "C_AuctionHouse", "C_TradeSkillUI.Craft", "C_Container.Use", "C_Container.Pickup",
    "C_Container.Split", "C_Item.Use", "C_Item.Equip", "C_Spell.Cast", "C_Spell.Pickup",
    "C_FriendList.Add", "C_FriendList.Send", "C_GuildInfo.Invite", "C_GuildInfo.Remove",
    "C_Mail", "C_Trade", "C_MerchantFrame", "C_PetBattles.Use",
    "CastSpell", "CastShapeshiftForm", "Pickup", "MoveForward", "MoveBackward", "MoveAndSteer",
    "StrafeLeft", "StrafeRight", "TurnLeft", "TurnRight", "TargetNearest", "TargetLast",
    "ChatEdit_", "ChatFrame_Send", "InviteUnit", "ClickSendMail", "ClickAuction",
)
_deny_parts = [re.escape(n) for n in DENY_EXACT] + [re.escape(n) + r"\w*" for n in DENY_PREFIX]
_DENY_RE = re.compile(r"(?<![A-Za-z0-9_])(?:" + "|".join(_deny_parts) + r")(?![A-Za-z0-9_])",
                      re.IGNORECASE)
_DENY_BRACKET = re.compile(r"C_(?:ChatInfo|Club|PartyInfo|Container|AuctionHouse)\s*\[", re.I)


def run_payload_hit(payload):
    """First deny-listed name in a Lua snippet, or None. Catches mistakes and obvious
    evasion (spaces around dots, bracket access, _G, loadstring); it is not a sandbox."""
    norm = re.sub(r"\s*([.:])\s*", ".", payload)
    for text in (payload, norm):
        m = _DENY_RE.search(text)
        if m:
            return m.group(0)
    m = _DENY_BRACKET.search(payload)
    return m.group(0) if m else None


def command_verdict(cmd, allow_unsafe=False):
    """(ok, reason). Pure: the whitelist, shape rules and the /run deny-list."""
    if not isinstance(cmd, str):
        return False, "command is not a string"
    if not cmd:
        return False, "empty command"
    if len(cmd) > MAX_CMD_LEN:
        return False, f"command is {len(cmd)} chars, limit is {MAX_CMD_LEN}"
    for ch in cmd:
        o = ord(ch)
        if o < 32 or o == 127:
            return False, f"control character U+{o:04X} (newlines and tabs are refused)"
        if o > 126:
            return False, f"non-ASCII character U+{o:04X} (typing is ASCII only)"
    if not cmd.startswith("/"):
        return False, "a typed command must start with '/'"
    rule = None
    for name, rx in _WHITELIST:
        if rx.match(cmd):
            rule = name
            break
    if rule is None:
        return False, ("not whitelisted: allowed are /reload, /fx, /fxdev, /run <lua>, "
                       "/console screenshotFormat <fmt>, /chatlog, /combatlog")
    if rule == "run" and not allow_unsafe:
        hit = run_payload_hit(cmd[len("/run "):])
        if hit:
            return False, f"/run payload mentions deny-listed API {hit!r} (--allow-unsafe is owner-only)"
    return True, rule


def check_command(cmd, allow_unsafe=False):
    ok, why = command_verdict(cmd, allow_unsafe)
    if not ok:
        raise Refused(f"refused: {why}", command=cmd if isinstance(cmd, str) else None)
    return why


# --------------------------------------------------------------------------
# game / window / input
# --------------------------------------------------------------------------
def game_pid(ctx):
    """pid of a process whose cmdline contains AppId=<appid>, else None."""
    rx = re.compile(rb"AppId=" + APPID.encode() + rb"(?!\d)")
    try:
        entries = os.listdir(ctx.proc_root)
    except OSError:
        return None
    for ent in sorted(entries):
        if not ent.isdigit() or int(ent) == os.getpid():
            continue
        try:
            with open(os.path.join(ctx.proc_root, ent, "cmdline"), "rb") as fh:
                data = fh.read(65536)
        except OSError:
            continue
        if rx.search(data.replace(b"\0", b" ")):
            return int(ent)
    return None


def x_env(ctx):
    env = dict(ctx.env)
    env["DISPLAY"] = ctx.env.get("FX_DISPLAY", ":0")
    auth = ctx.env.get("FX_XAUTHORITY")
    if not auth:
        found = sorted(glob.glob(os.path.join(ctx.run_dir, "xauth_*")),
                       key=lambda p: os.path.getmtime(p), reverse=True)
        if not found:
            raise FocusError(f"no X authority file {ctx.run_dir}/xauth_* (set FX_XAUTHORITY)")
        auth = found[0]
    env["XAUTHORITY"] = auth
    return env


class XInput:
    """xdotool wrapper with the focus guard. Nothing is sent unless the game owns focus."""

    def __init__(self, ctx):
        self.ctx = ctx
        self.env = x_env(ctx)

    def _x(self, *args, timeout=10):
        return self.ctx.run(["xdotool", *args], env=self.env, timeout=timeout)

    def windows(self):
        r = self._x("search", "--name", WINDOW_NAME)
        ids = [ln.strip() for ln in r.out.splitlines() if ln.strip().isdigit()]
        if len(ids) > 1:                    # several matches: keep exact-title windows
            exact = [i for i in ids if self._x("getwindowname", i).out.strip() == WINDOW_NAME]
            ids = exact or ids
        return ids

    def focus_name(self):
        r = self._x("getwindowfocus", "getwindowname")
        return r.out.strip() if r.rc == 0 else ""

    def focused(self):
        return self.focus_name() == WINDOW_NAME

    def activate(self):
        """Activate the game window; return its id or raise FocusError (nothing sent)."""
        ids = self.windows()
        if not ids:
            raise FocusError(f'no window named "{WINDOW_NAME}" (is the game running?)')
        for wid in ids[:3]:
            r = self._x("windowactivate", wid)
            if r.rc != 0:
                continue
            for _ in range(4):              # bounded settle: 4 x 0.3 s
                self.ctx.sleep(0.3)
                if self.focused():
                    return wid
        raise FocusError(f'could not give focus to "{WINDOW_NAME}"; sent nothing',
                         focus=self.focus_name())

    def send(self, cmd):
        """slash, type, Return, with the focus re-checked between every step."""
        text = cmd[1:]
        wid = self.activate()
        if not self.focused():
            raise FocusError("focus is not the game window; sent nothing", focus=self.focus_name())
        r = self._x("key", "slash")
        if r.rc != 0:
            raise FocusError("xdotool key slash failed", err=r.err.strip())
        self.ctx.sleep(0.6)
        if not self.focused():
            raise FocusError("focus left the game after the slash; typed nothing "
                             "(the chat box may be open in the game)", focus=self.focus_name())
        r = self._x("type", "--delay", "70", text, timeout=60)
        if r.rc != 0:
            raise FocusError("xdotool type failed", err=r.err.strip())
        self.ctx.sleep(0.3)
        if not self.focused():
            raise FocusError("focus left the game while typing; Return NOT sent",
                             focus=self.focus_name())
        r = self._x("key", "Return")
        if r.rc != 0:
            raise FocusError("xdotool key Return failed", err=r.err.strip())
        return wid


# --------------------------------------------------------------------------
# beacon cache + combat/group guard
# --------------------------------------------------------------------------
def state_path(ctx):
    return os.path.join(ctx.state_dir, "state.json")


def load_state(ctx):
    try:
        with open(state_path(ctx), encoding="utf-8") as fh:
            st = json.load(fh)
        return st if isinstance(st, dict) else {}
    except (OSError, ValueError):
        return {}


def save_state(ctx, beacon, shot):
    ctx.ensure_state_dir()
    atomic_write(state_path(ctx), json.dumps({"at": ctx.now(), "beacon": beacon, "shot": shot}))


def beacon_age(ctx, st=None):
    st = load_state(ctx) if st is None else st
    at = st.get("at")
    return None if not isinstance(at, (int, float)) else max(0.0, ctx.now() - at)


def combat_guard(ctx, force=False):
    """Refuse when the freshest beacon says combat or group (younger than 120 s)."""
    st = load_state(ctx)
    b = st.get("beacon")
    age = beacon_age(ctx, st)
    if not isinstance(b, dict) or not b.get("found") or age is None or age >= GUARD_MAX_AGE:
        return {"guard": "no fresh beacon"}
    why = [k for k in ("combat", "group") if b.get(k)]
    if not why:
        return {"guard": "clear", "beacon_age_s": round(age, 1)}
    info = {"beacon_age_s": round(age, 1), "state": why}
    if force:
        return {"guard": "FORCED past " + "+".join(why), **info}
    raise Refused(f"refused: the last beacon ({age:.0f} s old) says {' and '.join(why)}; "
                  "take a `shot` to refresh it (--force is owner-only)", **info)


def send_command(ctx, cmd, allow_unsafe=False, force=False, guard=True):
    check_command(cmd, allow_unsafe)
    info = combat_guard(ctx, force) if guard else {"guard": "skipped (shot)"}
    wid = XInput(ctx).send(cmd)
    return {"sent": cmd, "window": wid, **info}


# --------------------------------------------------------------------------
# SavedVariables through luajit in an empty environment
# --------------------------------------------------------------------------
LUA_SV = r'''
-- fxdev: load a SavedVariables file in an EMPTY environment, emit its globals as JSON.
local path = arg[1]
local MAX_NODES = tonumber(arg[2]) or 500000
local MAX_DEPTH = tonumber(arg[3]) or 40
local MAX_BYTES = tonumber(arg[4]) or 16777216
local MAX_TICKS = tonumber(arg[5]) or 100
local pcall, setfenv, loadstring, type, pairs, next, tostring, tonumber, error =
  pcall, setfenv, loadstring, type, pairs, next, tostring, tonumber, error
local sformat, sgsub, concat, sort, wr = string.format, string.gsub, table.concat, table.sort, io.write
local sethook, gcount, jitlib = debug.sethook, collectgarbage, jit

local function jstr(s)
  return '"' .. sgsub(s, '[%c"\\]', function(c)
    if c == '"' then return '\\"' elseif c == '\\' then return '\\\\'
    elseif c == '\n' then return '\\n' elseif c == '\r' then return '\\r'
    elseif c == '\t' then return '\\t' end
    return sformat('\\u%04x', c:byte())
  end) .. '"'
end
local function fail(msg) wr('{"ok":false,"error":' .. jstr(tostring(msg)) .. '}') os.exit(0) end

local fh = io.open(path, "rb")
if not fh then fail("cannot open file") end
local src = fh:read("*a")
fh:close()
if src:sub(1, 1) == "\27" then fail("refusing bytecode") end
local chunk, perr = loadstring(src, "=sv")
if not chunk then fail("syntax: " .. tostring(perr)) end
local env = {}
setfenv(chunk, env)
if jitlib then jitlib.off() end                -- count hooks only fire in the interpreter
local ticks = 0
sethook(function()
  ticks = ticks + 1
  if ticks > MAX_TICKS then error("instruction budget exceeded", 0) end
  if gcount("count") > 1048576 then error("memory budget exceeded", 0) end
end, "", 1000000)
local ok, err = pcall(chunk)
sethook()
if not ok then fail("chunk error: " .. tostring(err)) end

local nodes, bytes, truncated = 0, 0, false
local out = {}
local LIMIT = {}
local function emit(s)
  out[#out + 1] = s
  bytes = bytes + #s
  if bytes > MAX_BYTES then error(LIMIT, 0) end
end
local function num(n)
  if n ~= n then return '"<nan>"' elseif n == 1/0 then return '"<inf>"' elseif n == -1/0 then return '"<-inf>"' end
  local s = sformat("%.14g", n)
  if tonumber(s) ~= n then s = sformat("%.17g", n) end
  return s
end
local stack = {}
local function ser(v, depth)
  local t = type(v)
  if t == "string" then emit(jstr(v))
  elseif t == "number" then emit(num(v))
  elseif t == "boolean" then emit(v and "true" or "false")
  elseif t == "table" then
    nodes = nodes + 1
    if nodes > MAX_NODES then error(LIMIT, 0) end
    if stack[v] then truncated = true emit('"<cycle>"') return end
    if depth > MAX_DEPTH then truncated = true emit('"<depth limit>"') return end
    stack[v] = true
    local n, cnt = #v, 0
    for _ in pairs(v) do cnt = cnt + 1 end
    local isarr = true
    if cnt ~= n then isarr = false else for i = 1, n do if v[i] == nil then isarr = false break end end end
    if cnt == 0 then emit("[]")
    elseif isarr then
      emit("[")
      for i = 1, n do if i > 1 then emit(",") end ser(v[i], depth + 1) end
      emit("]")
    else
      local keys = {}
      for k, val in pairs(v) do
        local kt, ks = type(k), nil
        if kt == "string" then ks = k elseif kt == "number" then ks = num(k):gsub('"', '')
        elseif kt == "boolean" then ks = tostring(k) else ks = "<" .. kt .. ">" end
        keys[#keys + 1] = {ks, val}
      end
      sort(keys, function(a, b) return a[1] < b[1] end)
      emit("{")
      for i, kv in ipairs(keys) do
        if i > 1 then emit(",") end
        emit(jstr(kv[1])) emit(":") ser(kv[2], depth + 1)
      end
      emit("}")
    end
    stack[v] = nil
  else emit(jstr("<" .. t .. ">")) end
end

local names = {}
for k in pairs(env) do if type(k) == "string" then names[#names + 1] = k end end
sort(names)
local sok, serr = pcall(function()
  emit('{"ok":true,"globals":{')
  for i, k in ipairs(names) do
    if i > 1 then emit(",") end
    emit(jstr(k)) emit(":") ser(env[k], 1)
  end
  emit('},"nodes":' .. nodes .. ',"truncated":' .. (truncated and "true" or "false") .. '}')
end)
if not sok then
  if serr == LIMIT then fail("size limit exceeded") end
  fail("serialise: " .. tostring(serr))
end
wr(concat(out))
'''


def wait_stable(ctx, path, timeout=10.0, interval=0.3):
    """Return (mtime_ns, size) once two reads `interval` apart agree (client may be mid-write)."""
    deadline = ctx.now() + timeout
    last = None
    while True:
        try:
            st = os.stat(path)
            sig = (st.st_mtime_ns, st.st_size)
        except OSError:
            sig = None
        if sig is not None and sig == last:
            return sig
        last = sig
        if ctx.now() >= deadline:
            raise TimedOut(f"{path} did not settle within {timeout:.0f} s" if sig else f"{path} does not exist")
        ctx.sleep(interval)


def parse_sv_file(ctx, path, timeout=10.0, tries=2):
    """Globals of a SavedVariables file as a dict, via luajit in an empty environment."""
    last_err = None
    for _ in range(tries):
        sig = wait_stable(ctx, path, timeout=timeout)
        if sig[1] > MAX_SV_BYTES:
            raise FxError(f"{path} is {sig[1]} bytes; refusing files over {MAX_SV_BYTES}")
        r = ctx.run(["luajit", "-", path], input=LUA_SV, timeout=timeout,
                    limits={"cpu": int(timeout) + 2, "as": 4 << 30})
        if r.timed_out:
            raise TimedOut(f"luajit timed out parsing {path} after {timeout:.0f} s (killed)")
        try:
            doc = json.loads(r.out)
        except ValueError:
            raise FxError(f"luajit produced no JSON for {path} (rc {r.rc}): {r.err.strip()[:300]}")
        if doc.get("ok"):
            return doc["globals"], doc
        last_err = doc.get("error", "unknown error")
        try:
            st = os.stat(path)
            if (st.st_mtime_ns, st.st_size) == sig:
                break                           # file did not change: a real parse failure
        except OSError:
            pass
    raise FxError(f"SavedVariables parse failed for {path}: {last_err}")


def select_path(value, path):
    """Dotted selection into parsed JSON. Lua arrays are 1-based; -1 is the last element."""
    if not path:
        return value
    cur = value
    walked = []
    for seg in path.split("."):
        where = ".".join(walked) or "<root>"
        if seg == "":
            raise FxError(f"empty segment in path {path!r}")
        if isinstance(cur, list):
            try:
                idx = int(seg)
            except ValueError:
                raise FxError(f"{where} is a list ({len(cur)} items): use a 1-based index, -1 = last")
            if idx == 0 or idx > len(cur) or idx < -len(cur):
                raise FxError(f"index {idx} out of range at {where} (list has {len(cur)} items)")
            cur = cur[idx - 1] if idx > 0 else cur[idx]
        elif isinstance(cur, dict):
            if seg not in cur:
                raise FxError(f"no key {seg!r} at {where}; keys: {sorted(cur)[:20]}")
            cur = cur[seg]
        else:
            raise FxError(f"{where} is a scalar, cannot descend into {seg!r}")
        walked.append(seg)
    return cur


def file_info(ctx, path):
    try:
        st = os.stat(path)
    except OSError:
        return {"path": path, "exists": False}
    return {"path": path, "exists": True, "size": st.st_size, "mtime": iso(st.st_mtime),
            "age_s": round(max(0.0, ctx.now() - st.st_mtime), 1)}


def read_sv(ctx, which, path_sel=None, timeout=10.0):
    fname, glob_name = SV_FILES[which]
    path = ctx.sv_path(which)
    if not os.path.exists(path):
        raise FxError(f"{path} does not exist yet (SavedVariables are written at /reload or logout)")
    globs, doc = parse_sv_file(ctx, path, timeout=timeout)
    if glob_name not in globs:
        raise FxError(f"{fname} does not define {glob_name} (globals: {sorted(globs)})")
    value = select_path(globs[glob_name], path_sel)
    return {"ok": True, "file": file_info(ctx, path), "global": glob_name, "path": path_sel or "",
            "untrusted_data": True, "truncated": doc.get("truncated", False), "value": value}


# --------------------------------------------------------------------------
# DevCommands.lua / DevStamp.lua
# --------------------------------------------------------------------------
def lua_quote(s):
    """A safe Lua double-quoted string literal for any text (non-printables as \\ddd)."""
    out = ['"']
    for b in s.encode("utf-8", "replace"):
        if b == 0x22:
            out.append('\\"')
        elif b == 0x5C:
            out.append("\\\\")
        elif b == 0x0A:
            out.append("\\n")
        elif b == 0x0D:
            out.append("\\r")
        elif b == 0x09:
            out.append("\\t")
        elif 32 <= b < 127:
            out.append(chr(b))
        else:
            out.append(f"\\{b:03d}")
    out.append('"')
    return "".join(out)


def render_devcommands(entries, header=""):
    """entries: [("verb", text) | ("lua", code)] -> contents of DevCommands.lua."""
    lines = ["-- generated by scripts/fxdev.py; do not edit by hand" + (f" ({header})" if header else ""),
             "ForteDevCommands = {"]
    for kind, text in entries:
        if kind == "lua":
            lines.append(f"\t{{ lua = {lua_quote(text)} }},")
        else:
            lines.append(f"\t{lua_quote(text)},")
    lines.append("}")
    return "\n".join(lines) + "\n"


def parse_commands_args(tokens):
    """Order-preserving parse of `commands`: verbs, `--lua CODE`, `--allow-unsafe`."""
    entries, allow, i = [], False, 0
    while i < len(tokens):
        t = tokens[i]
        if t == "--lua":
            if i + 1 >= len(tokens):
                raise Refused("--lua needs a code argument")
            entries.append(("lua", tokens[i + 1]))
            i += 2
            continue
        if t.startswith("--lua="):
            entries.append(("lua", t[len("--lua="):]))
        elif t == "--allow-unsafe":
            allow = True
        elif t.startswith("--"):
            raise Refused(f"unknown option {t} for `commands`")
        else:
            entries.append(("verb", t))
        i += 1
    return entries, allow


def check_devcommand_entries(entries, allow_unsafe=False):
    for kind, text in entries:
        if kind == "verb":
            if not text.strip() or len(text) > MAX_CMD_LEN:
                raise Refused(f"verb {text[:40]!r}: empty or longer than {MAX_CMD_LEN}")
            if text.startswith("/"):
                raise Refused(f"verb {text!r} starts with '/': give the verb only, or use --lua")
            if any(ord(c) < 32 or ord(c) == 127 for c in text):
                raise Refused(f"verb {text[:40]!r} contains control characters")
        else:
            if not text.strip() or len(text) > MAX_LUA_CODE:
                raise Refused(f"--lua code is empty or longer than {MAX_LUA_CODE} chars")
            if "\x00" in text:
                raise Refused("--lua code contains a NUL byte")
            if not allow_unsafe:
                hit = run_payload_hit(text)
                if hit:
                    raise Refused(f"--lua code mentions deny-listed API {hit!r} "
                                  "(--allow-unsafe is owner-only)")


def install_dev_dir(ctx):
    d = os.path.join(ctx.addons_dir, "Forte_Dev")
    if os.path.islink(d) or not os.path.isdir(d):
        raise FxError(f"{d} is missing or a symlink: run `fxdev.py deploy` first")
    return d


def write_devcommands(ctx, entries, allow_unsafe=False):
    check_devcommand_entries(entries, allow_unsafe)
    d = install_dev_dir(ctx)
    path = os.path.join(d, "DevCommands.lua")
    if os.path.islink(path):
        raise FxError(f"{path} is a symlink; refusing to write through it")
    existed = os.path.exists(path)
    atomic_write(path, render_devcommands(entries, utc_stamp_time(ctx.now())))
    res = {"ok": True, "path": path, "count": len(entries),
           "entries": [{"lua": t} if k == "lua" else t for k, t in entries],
           "new_file": not existed, "restart_needed": not existed,
           "next": "the game runs these ~3 s after the next login/reload (never in combat)"}
    if not existed:
        res["note"] = "DevCommands.lua did not exist: the client only discovers new files at a full restart"
    return res


def git_stamp(ctx):
    """'<short sha>[+dirty]+<UTC>' (sha is 'nogit' if git cannot answer)."""
    sha = "nogit"
    r = ctx.run(["git", "-C", ctx.root, "rev-parse", "--short", "HEAD"], timeout=15)
    if r.rc == 0 and re.fullmatch(r"[0-9a-f]{4,40}", r.out.strip()):
        sha = r.out.strip()
    dirty = False
    if sha != "nogit":
        d = ctx.run(["git", "-C", ctx.root, "--no-optional-locks", "status", "--porcelain",
                     "--", "addon", "dev"], timeout=30)
        dirty = d.rc == 0 and bool(d.out.strip())
    return f"{sha}{'+dirty' if dirty else ''}+{utc_stamp_time(ctx.now())}"


# --------------------------------------------------------------------------
# deploy planning + execution
# --------------------------------------------------------------------------
def repo_trees(root):
    """[(name, src_dir, excluded dir parts, excluded suffixes, is_dev)] in deploy order."""
    trees = []
    for d in sorted(glob.glob(os.path.join(root, "addon", "Forte_*"))):
        if os.path.isdir(d) and glob.glob(os.path.join(d, "*.toc")):
            trees.append((os.path.basename(d), d, ADDON_EXCLUDE_DIRS, ADDON_EXCLUDE_SUFFIXES, False))
    dev = os.path.join(root, "dev", "Forte_Dev")
    if os.path.isdir(dev):
        trees.append(("Forte_Dev", dev, DEV_EXCLUDE_DIRS, (), True))
    return trees


def tree_files(src, excl_dirs, excl_suffixes, is_dev):
    """Sorted repo-relative (POSIX) paths of the files an install must carry."""
    out = []
    for base, dirs, files in os.walk(src):
        dirs[:] = sorted(d for d in dirs if d not in excl_dirs and not d.startswith(".")
                         and d != "__pycache__")
        for f in sorted(files):
            full = os.path.join(base, f)
            rel = os.path.relpath(full, src).replace(os.sep, "/")
            if f.startswith(".") or f.lower().endswith(excl_suffixes) or not os.path.isfile(full) \
                    or os.path.islink(full):
                continue
            if is_dev and rel in GENERATED:
                continue
            out.append(rel)
    return sorted(out)


def same_bytes(a, b):
    try:
        if os.path.getsize(a) != os.path.getsize(b):
            return False
        with open(a, "rb") as fa, open(b, "rb") as fb:
            while True:
                x, y = fa.read(1 << 20), fb.read(1 << 20)
                if x != y:
                    return False
                if not x:
                    return True
    except OSError:
        return False


def plan_deploy(ctx):
    """Read-only comparison repo vs install. Returns a plan dict; writes nothing."""
    addons = ctx.addons_dir
    if not os.path.isdir(addons):
        raise FxError(f"AddOns dir does not exist: {addons} (never created by this tool)")
    plan = {"addons_dir": addons, "trees": [], "skipped": [], "new": [], "changed": [],
            "same": 0, "extra": [], "toc_changed": []}
    for name, src, excl_d, excl_s, is_dev in repo_trees(ctx.root):
        dst = os.path.join(addons, name)
        tree = {"name": name, "src": src, "dst": dst, "is_dev": is_dev, "files": []}
        if os.path.islink(dst):
            tgt = os.path.realpath(dst)
            plan["skipped"].append({"addon": name, "reason": "install is a symlink"
                                    + (" into this repo (already live; just /reload)"
                                       if tgt.startswith(os.path.realpath(ctx.root) + os.sep)
                                       else f" to {tgt}; refusing to write through it")})
            continue
        if os.path.lexists(dst) and not os.path.isdir(dst):
            plan["skipped"].append({"addon": name, "reason": "install entry is not a directory"})
            continue
        rels = tree_files(src, excl_d, excl_s, is_dev)
        for rel in rels:
            s, d = os.path.join(src, rel), os.path.join(dst, *rel.split("/"))
            if os.path.islink(d):
                plan["skipped"].append({"file": f"{name}/{rel}", "reason": "install file is a symlink"})
                continue
            if not os.path.exists(d):
                state = "new"
                plan["new"].append(f"{name}/{rel}")
            elif same_bytes(s, d):
                plan["same"] += 1
                continue
            else:
                state = "changed"
                plan["changed"].append(f"{name}/{rel}")
                if rel.endswith(".toc"):
                    plan["toc_changed"].append(f"{name}/{rel}")
            tree["files"].append((rel, state))
        if os.path.isdir(dst):
            want = set(rels) | (set(GENERATED) if is_dev else set())
            for base, dirs, files in os.walk(dst):
                dirs[:] = [x for x in dirs if x not in excl_d and not x.startswith(".")]
                for f in files:
                    rel = os.path.relpath(os.path.join(base, f), dst).replace(os.sep, "/")
                    if rel not in want and not f.startswith(".") and not f.lower().endswith(excl_s):
                        plan["extra"].append(f"{name}/{rel}")
        plan["trees"].append(tree)
    return plan


def _inside(base, path):
    base, path = os.path.realpath(base), os.path.realpath(path)
    return path == base or path.startswith(base + os.sep)


def copy_into(addon_dir, rel, src):
    """Copy one file into the install tree, refusing to leave `addon_dir`. True if written."""
    dst = os.path.join(addon_dir, *rel.split("/"))
    parent = os.path.dirname(dst)
    os.makedirs(parent, exist_ok=True)
    if not _inside(addon_dir, parent) or os.path.islink(dst):
        return False
    with open(src, "rb") as fh:
        atomic_write(dst, fh.read())
    return True


def deploy(ctx, dry_run=False):
    plan = plan_deploy(ctx)
    reasons = [f"new file {p}" for p in plan["new"]] + [f"toc changed {p}" for p in plan["toc_changed"]]
    gen_new = []
    dev_tree = next((t for t in plan["trees"] if t["is_dev"]), None)
    dev_dir = os.path.join(ctx.addons_dir, "Forte_Dev")
    if dev_tree is not None:
        for g in GENERATED:
            if not os.path.exists(os.path.join(dev_dir, g)):
                gen_new.append(f"Forte_Dev/{g}")
    reasons += [f"new file {p}" for p in gen_new]
    stamp = git_stamp(ctx)
    res = {"ok": True, "dry_run": dry_run, "stamp": stamp, "addons_dir": plan["addons_dir"],
           "copied": [], "new": plan["new"] + gen_new, "changed": plan["changed"],
           "toc_changed": plan["toc_changed"], "unchanged": plan["same"],
           "skipped": plan["skipped"], "extra_in_install": plan["extra"][:50],
           "restart_needed": bool(reasons), "restart_reasons": reasons[:12],
           "reload_needed": False, "stamp_written": False}
    if dev_tree is None:
        res["warning"] = "dev/Forte_Dev is not in the repo: no DevStamp.lua / DevCommands.lua written"
    if dry_run:
        res["would_copy"] = [f"{t['name']}/{rel}" for t in plan["trees"] for rel, _ in t["files"]]
        return res
    for t in plan["trees"]:
        dst = t["dst"]
        fresh = not os.path.isdir(dst)
        for rel, _state in t["files"]:
            if copy_into(dst, rel, os.path.join(t["src"], *rel.split("/"))):
                res["copied"].append(f"{t['name']}/{rel}")
            else:
                res["skipped"].append({"file": f"{t['name']}/{rel}", "reason": "path escapes the addon folder"})
        if fresh and os.path.isdir(dst) and not os.path.exists(os.path.join(dst, MARKER)):
            atomic_write(os.path.join(dst, MARKER), "ForteXorcist fxdev.py deploy\n")
    if dev_tree is not None:
        if os.path.islink(dev_dir):
            res["skipped"].append({"addon": "Forte_Dev", "reason": "install is a symlink"})
        else:
            atomic_write(os.path.join(dev_dir, "DevStamp.lua"), f'ForteDevStamp = {lua_quote(stamp)}\n')
            res["stamp_written"] = True
            cmds = os.path.join(dev_dir, "DevCommands.lua")
            if not os.path.exists(cmds):
                atomic_write(cmds, render_devcommands([], utc_stamp_time(ctx.now())))
    res["reload_needed"] = bool(res["copied"]) or res["stamp_written"]
    if res["restart_needed"]:
        res["next"] = ("a file or toc line is NEW to the install: the client only discovers it at a full "
                       "restart. Ask the owner to quit and relaunch the game; /reload is not enough.")
    elif res["reload_needed"]:
        res["next"] = "run `fxdev.py reload` (code is re-read at /reload)"
    return res


# --------------------------------------------------------------------------
# screenshots + beacon
# --------------------------------------------------------------------------
def list_shots(ctx, pattern="WoWScrnShot_*"):
    """{name: (mtime_ns, size)} of the game's screenshots."""
    out = {}
    for p in glob.glob(os.path.join(ctx.shots_dir, pattern)):
        try:
            st = os.stat(p)
        except OSError:
            continue
        out[os.path.basename(p)] = (st.st_mtime_ns, st.st_size)
    return out


def newest_shot(ctx):
    shots = list_shots(ctx)
    if not shots:
        return None
    name = max(shots, key=lambda n: shots[n][0])
    return os.path.join(ctx.shots_dir, name)


def _open_rgb(path):
    from PIL import Image
    with Image.open(path) as im:
        im.load()
        return im.convert("RGB")


def wait_new_shot(ctx, before, timeout=20.0, interval=0.5):
    """(path, RGB image) of a PNG that is new since `before` and has a stable size."""
    deadline = ctx.now() + timeout
    last_sig, hint = None, None
    while True:
        cur = list_shots(ctx)
        fresh = [n for n in cur if cur[n] != before.get(n)]
        png = [n for n in fresh if n.lower().endswith(".png")]
        if fresh and not png:
            hint = f"a new non-PNG screenshot appeared ({fresh[0]}): run `type \"/console screenshotFormat png\"`"
        if png:
            name = max(png, key=lambda n: cur[n][0])
            sig = (name, cur[name])
            if sig == last_sig and cur[name][1] > 0:
                path = os.path.join(ctx.shots_dir, name)
                try:
                    return path, _open_rgb(path)
                except Exception:                       # truncated mid-write: keep waiting
                    pass
            last_sig = sig
        if ctx.now() >= deadline:
            raise TimedOut(hint or f"no new screenshot within {timeout:.0f} s "
                           "(game focused? Forte_Dev installed and loaded?)")
        ctx.sleep(interval)


def _classify(r, g, b):
    """1 = magenta-ish, 2 = cyan-ish, 0 = neither (tolerant of JPEG noise)."""
    if r >= 140 and b >= 140 and g <= 100 and min(r, b) - g >= 60:
        return 1
    if g >= 140 and b >= 140 and r <= 100 and min(g, b) - r >= 60:
        return 2
    return 0


def _components(points):
    """8-connected components of a set of (x, y): [(minx, miny, maxx, maxy, area)]."""
    seen, comps = set(), []
    for p in points:
        if p in seen:
            continue
        seen.add(p)
        stack, area = [p], 0
        x0 = x1 = p[0]
        y0 = y1 = p[1]
        while stack:
            x, y = stack.pop()
            area += 1
            x0, x1, y0, y1 = min(x0, x), max(x1, x), min(y0, y), max(y1, y)
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    q = (x + dx, y + dy)
                    if q in points and q not in seen:
                        seen.add(q)
                        stack.append(q)
        comps.append((x0, y0, x1, y1, area))
    return comps


BIT_NAMES = {1: "combat", 2: "group", 3: "running", 4: "finished", 5: "failed", 6: "errors"}


def decode_beacon(img):
    """Decode the 16-cell beacon from a screenshot (PIL image). `{found: False, ...}` if absent."""
    W, H = img.size
    rw, rh = max(1, int(W * 0.12)), max(1, int(H * 0.06))
    region = img.convert("RGB").crop((0, 0, rw, rh))
    data = region.tobytes()
    mag, cya = set(), set()
    for i in range(0, len(data), 3):
        c = _classify(data[i], data[i + 1], data[i + 2])
        if c:
            p = (i // 3) % rw, (i // 3) // rw
            (mag if c == 1 else cya).add(p)
    mcs = [c for c in _components(mag) if c[4] >= 12 and c[2] - c[0] >= 2 and c[3] - c[1] >= 2]
    ccs = [c for c in _components(cya) if c[4] >= 12 and c[2] - c[0] >= 2 and c[3] - c[1] >= 2]
    best = None
    for m in mcs:
        for c in ccs:
            x0, x1 = m[0], c[2] + 1
            span = x1 - x0
            if c[0] <= m[2] or span < 16 * 3:
                continue
            cell = span / 16.0
            tol = max(2.5, 0.3 * cell)
            ok = True
            for comp in (m, c):
                w, h = comp[2] - comp[0] + 1, comp[3] - comp[1] + 1
                if abs(w - cell) > tol or abs(h - cell) > tol or comp[4] < 0.55 * w * h:
                    ok = False
            if not ok or abs(m[1] - c[1]) > tol or abs(m[3] - c[3]) > tol:
                continue
            score = abs(m[2] - m[0] + 1 - cell) + abs(c[2] - c[0] + 1 - cell) + abs(m[1] - c[1])
            if best is None or score < best[0]:
                best = (score, m, c, cell)
    if best is None:
        return {"found": False, "reason": "no magenta+cyan cell pair of matching size in the top-left 12% x 6%"}
    _, m, c, cell = best
    x0 = m[0]
    cy = int(((m[1] + m[3] + 1) + (c[1] + c[3] + 1)) / 4.0)

    def sample(i):
        cx = int(x0 + (i + 0.5) * cell)
        tot = [0, 0, 0]
        n = 0
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                x, y = min(max(cx + dx, 0), rw - 1), min(max(cy + dy, 0), rh - 1)
                o = (y * rw + x) * 3
                for k in range(3):
                    tot[k] += data[o + k]
                n += 1
        return tuple(t / n for t in tot)

    first, last = sample(0), sample(15)
    if _classify(*(int(v) for v in first)) != 1 or _classify(*(int(v) for v in last)) != 2:
        return {"found": False, "reason": "end cells are not magenta/cyan at their centres"}
    bits = []
    for i in range(1, 15):
        px = sample(i)
        if max(px) - min(px) > 100:
            return {"found": False, "reason": f"cell {i} is coloured, not black/white (false match)"}
        bits.append(1 if sum(px) / 3.0 >= 127.5 else 0)
    run_id = 0
    for b in bits[6:14]:                     # cells 7..14, cell 7 = most significant
        run_id = (run_id << 1) | b
    out = {"found": True}
    for idx, name in BIT_NAMES.items():
        out[name] = bool(bits[idx - 1])
    out["runId8"] = run_id
    out["cell_px"] = round(cell, 2)
    out["origin"] = [x0, m[1]]
    return out


def write_crops(ctx, img):
    d = ctx.ensure_state_dir()
    W, H = img.size
    paths = {"panel": os.path.join(d, "panel.png"), "chat": os.path.join(d, "chat.png"),
             "overview": os.path.join(d, "overview.png")}
    img.crop((0, 0, int(W * 0.30), int(H * 0.45))).save(paths["panel"])
    img.crop((0, int(H * 0.72), int(W * 0.24), H)).save(paths["chat"])
    from PIL import Image
    ow = 1600
    ov = img if W <= ow else img.resize((ow, max(1, round(H * ow / W))), Image.LANCZOS)
    ov.save(paths["overview"])
    return paths


def do_shot(ctx, timeout=20.0, file=None):
    """One screenshot round: type /fxdev shot, wait for the PNG, decode, crop, cache."""
    if file:
        if not os.path.isfile(file):
            raise FxError(f"no such file: {file}")
        path, img, sent, update = file, _open_rgb(file), None, False
    else:
        before = list_shots(ctx)
        sent = send_command(ctx, "/fxdev shot", guard=False)
        path, img = wait_new_shot(ctx, before, timeout)
        update = True
    beacon = decode_beacon(img)
    crops = write_crops(ctx, img)
    if update:
        save_state(ctx, beacon, path)
    res = {"ok": True, "screenshot": path, "size": list(img.size), "beacon": beacon,
           "crops": crops, "state_updated": update}
    if not beacon.get("found"):
        res["warning"] = ("beacon not found: Forte_Dev not loaded, panel off, or the screenshot "
                          "does not show the top-left corner; read the crops")
    if sent:
        res["window"] = sent["window"]
    return res


# --------------------------------------------------------------------------
# verbs
# --------------------------------------------------------------------------
def v_status(ctx, a):
    res = {"ok": True}
    pid = game_pid(ctx)
    res["game_running"] = pid is not None
    res["game_pid"] = pid
    try:
        res["window_id"] = (XInput(ctx).windows() or [None])[0]
    except FxError as e:
        res["window_id"] = None
        res["window_error"] = str(e)
    res["wow_dir"] = ctx.wow_dir
    try:
        res["account"] = ctx.account()
    except FxError as e:
        res["account"] = None
        res["account_error"] = str(e)
    try:
        p = plan_deploy(ctx)
        res["install"] = {"addons_dir": p["addons_dir"],
                          "in_sync": not (p["new"] or p["changed"]),
                          "missing_in_install": p["new"][:50], "different": p["changed"][:50],
                          "toc_changed": p["toc_changed"], "extra_in_install": p["extra"][:50],
                          "unchanged": p["same"], "skipped": p["skipped"]}
    except FxError as e:
        res["install"] = {"error": str(e)}
    res["dev_stamp"] = dev_stamp_status(ctx)
    sv = {}
    for which in ("core", "dev"):
        try:
            sv[which] = file_info(ctx, ctx.sv_path(which))
        except FxError as e:
            sv[which] = {"error": str(e)}
    res["sv"] = sv
    np_ = newest_shot(ctx)
    res["newest_screenshot"] = file_info(ctx, np_) if np_ else None
    st = load_state(ctx)
    age = beacon_age(ctx, st)
    res["beacon"] = {"cached": st.get("beacon"), "age_s": None if age is None else round(age, 1),
                     "blocks_typing": bool(isinstance(st.get("beacon"), dict) and st["beacon"].get("found")
                                           and (st["beacon"].get("combat") or st["beacon"].get("group"))
                                           and age is not None and age < GUARD_MAX_AGE)}
    return res


def dev_stamp_status(ctx):
    out = {"install": None, "last_run": None, "match": None}
    path = os.path.join(ctx.addons_dir, "Forte_Dev", "DevStamp.lua")
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            m = re.search(r'ForteDevStamp\s*=\s*"([^"\n]*)"', fh.read(4096))
        out["install"] = m.group(1) if m else None
    except OSError:
        out["install_error"] = "DevStamp.lua not in the install"
    try:
        r = read_sv(ctx, "dev", timeout=5)
        db = r["value"] if isinstance(r["value"], dict) else {}
        runs = db.get("runs") if isinstance(db.get("runs"), list) else []
        out["last_run"] = db.get("stamp") or (runs[-1].get("stamp") if runs and isinstance(runs[-1], dict) else None)
        out["sv_age_s"] = r["file"].get("age_s")
    except FxError as e:
        out["last_run_error"] = str(e)
    if out["install"] and out["last_run"]:
        out["match"] = out["install"] == out["last_run"]
    return out


def v_deploy(ctx, a):
    return deploy(ctx, dry_run=a.dry_run)


def v_commands(ctx, tokens):
    entries, allow = parse_commands_args(tokens)
    return write_devcommands(ctx, entries, allow)


def v_type(ctx, a):
    res = send_command(ctx, a.command, allow_unsafe=a.allow_unsafe, force=a.force)
    return {"ok": True, **res}


def sv_sigs(ctx):
    sigs = {}
    for which in ("core", "dev"):
        try:
            p = ctx.sv_path(which)
            st = os.stat(p)
            sigs[p] = (st.st_mtime_ns, st.st_size)
        except (OSError, FxError):
            pass
    return sigs


def do_reload(ctx, timeout=45.0, settle=4.0, force=False):
    ctx.account()                                       # fail early if no account folder
    before = sv_sigs(ctx)
    sent = send_command(ctx, "/reload", force=force)
    t0 = ctx.now()
    deadline = t0 + timeout
    last = None
    while True:
        cur = sv_sigs(ctx)
        changed = sorted(p for p, s in cur.items() if before.get(p) != s)
        if changed and cur == last:
            break
        last = cur
        if ctx.now() >= deadline:
            raise TimedOut("SavedVariables unchanged after /reload: the reload may not have happened",
                           sent=sent["sent"], waited_s=round(ctx.now() - t0, 1))
        ctx.sleep(0.5)
    waited = round(ctx.now() - t0, 1)
    ctx.sleep(settle)
    return {"ok": True, "reloaded": True, "waited_s": waited, "settle_s": settle,
            "changed": [os.path.basename(p) for p in changed], "window": sent["window"],
            "guard": sent.get("guard")}


def v_reload(ctx, a):
    return do_reload(ctx, a.timeout, a.settle, a.force)


def v_shot(ctx, a):
    return do_shot(ctx, a.timeout, a.file)


def v_sv(ctx, a):
    return read_sv(ctx, a.which, a.path)


def v_errors(ctx, a):
    r = read_sv(ctx, "core", "errors")
    return r


SUITE_RE = re.compile(r"^[A-Za-z0-9_.-]{1,40}$")


def do_selftest(ctx, suite=None, timeout=60.0, poll=4.0, force=False):
    if suite is not None and not SUITE_RE.match(suite):
        raise Refused(f"suite name {suite!r} must match [A-Za-z0-9_.-]{{1,40}}")
    cmd = "/fxdev selftest" + (f" {suite}" if suite else "")
    check_command(cmd)
    st = load_state(ctx)
    age = beacon_age(ctx, st)
    baseline = None
    if not isinstance(st.get("beacon"), dict) or age is None or age >= GUARD_MAX_AGE:
        baseline = do_shot(ctx, timeout=min(20.0, timeout))     # fresh combat/group + run id
        st = load_state(ctx)
    guard = combat_guard(ctx, force)
    b0 = st.get("beacon") if isinstance(st.get("beacon"), dict) else {}
    before_id = b0.get("runId8") if b0.get("found") else None
    sent = send_command(ctx, cmd, force=force, guard=False)
    t0 = ctx.now()
    polls, shot = 0, None
    while True:
        ctx.sleep(poll)
        shot = do_shot(ctx, timeout=min(20.0, max(5.0, timeout - (ctx.now() - t0))))
        polls += 1
        b = shot["beacon"]
        done = (b.get("found") and b.get("finished") and not b.get("running")
                and (before_id is None or b.get("runId8") != before_id))
        elapsed = round(ctx.now() - t0, 1)
        if done:
            res = {"ok": True, "finished": True, "suite": suite, "runId8_before": before_id,
                   "baseline_found": before_id is not None, "polls": polls, "elapsed_s": elapsed,
                   "passed": not b.get("failed"), "beacon": b, "screenshot": shot["screenshot"],
                   "crops": shot["crops"], "guard": guard, "window": sent["window"],
                   "note": ("full results reach ForteDevDB only after the next reload: "
                            "`fxdev.py reload` then `fxdev.py sv dev --path runs.-1`")}
            if before_id is None:
                res["warning"] = "no baseline beacon: a previous finished run could be mistaken for this one"
            return res
        if ctx.now() - t0 >= timeout:
            raise TimedOut(f"selftest not finished after {timeout:.0f} s ({polls} polls); the beacon below "
                           "is the last reading", beacon=b, screenshot=shot["screenshot"],
                           crops=shot["crops"], runId8_before=before_id, polls=polls)


def v_selftest(ctx, a):
    return do_selftest(ctx, a.suite, a.timeout, a.poll, a.force)


def run_summary(sv_dev_value):
    """Compact view of the newest ForteDevDB run."""
    db = sv_dev_value if isinstance(sv_dev_value, dict) else {}
    runs = db.get("runs") if isinstance(db.get("runs"), list) else []
    if not runs or not isinstance(runs[-1], dict):
        return None
    run = runs[-1]
    tests = run.get("tests") if isinstance(run.get("tests"), list) else []
    failing = [{"name": t.get("name"), "detail": t.get("detail")} for t in tests
               if isinstance(t, dict) and t.get("status") == "fail"][:12]
    return {k: run.get(k) for k in ("id", "stamp", "suite", "combat", "pass", "fail", "skip")} | {
        "failing": failing, "build": db.get("build")}


def v_loop(ctx, a):
    """One iteration, no repeats: deploy -> reload -> selftest -> shot -> reload -> read."""
    res = {"ok": False, "steps": {}}
    bulky = ("copied", "would_copy", "extra_in_install", "entries", "value")

    def step(name, fn):
        try:
            out = fn()
        except FxError as e:
            res["steps"][name] = {"ok": False, "error": str(e)}
            e.extra = {**e.extra, "failed_step": name, "steps": res["steps"],
                       **{k: res[k] for k in ("stamp",) if k in res}}
            raise
        res["steps"][name] = {k: v for k, v in out.items() if k not in bulky}
        return out

    if game_pid(ctx) is None:
        raise FxError("the game is not running (no process with AppId=%s)" % APPID)
    d = step("deploy", lambda: deploy(ctx))
    res["stamp"] = d["stamp"]
    if d["restart_needed"]:
        raise OwnerAction("deployed, but a file or toc line is new to the install: the owner must quit "
                          "and relaunch the game once; stopping before any input",
                          restart_reasons=d["restart_reasons"], steps=res["steps"], stamp=d["stamp"])
    step("reload1", lambda: do_reload(ctx, a.timeout, a.settle, a.force))
    step("selftest", lambda: do_selftest(ctx, a.suite, a.selftest_timeout, 4.0, a.force))
    step("shot", lambda: do_shot(ctx))
    step("reload2", lambda: do_reload(ctx, a.timeout, a.settle, a.force))
    dev = step("read_dev", lambda: read_sv(ctx, "dev"))
    run = run_summary(dev["value"])
    res["run"] = run
    res["stamp_match"] = bool(run and run.get("stamp") == d["stamp"])
    try:
        res["errors"] = read_sv(ctx, "core", "errors")["value"]
    except FxError as e:
        res["errors"] = {"error": str(e)}
    res["ok"] = True
    return res


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------
def build_parser():
    ap = argparse.ArgumentParser(
        prog="fxdev.py", description=__doc__.split("\n\n")[0],
        epilog="`commands [VERB ...] [--lua CODE ...]` writes Forte_Dev/DevCommands.lua "
               "(no arguments clears it). See docs/dev-loop.md.")
    sub = ap.add_subparsers(dest="verb", required=True, metavar="VERB")
    sub.add_parser("status", help="game, window, install vs repo, stamps, SV mtimes, newest screenshot")
    p = sub.add_parser("deploy", help="copy changed addon/Forte_* + dev/Forte_Dev into the install")
    p.add_argument("--dry-run", action="store_true")
    sub.add_parser("commands", help="write DevCommands.lua (verbs and --lua entries)").add_argument(
        "rest", nargs="*")
    p = sub.add_parser("type", help="type one whitelisted slash command into the game")
    p.add_argument("command")
    p.add_argument("--force", action="store_true", help="OWNER ONLY: ignore the combat/group guard")
    p.add_argument("--allow-unsafe", action="store_true",
                   help="OWNER ONLY: skip the /run deny-list (never used by the agent)")
    p = sub.add_parser("reload", help="type /reload, wait for the SavedVariables mtime to change")
    p.add_argument("--force", action="store_true")
    p.add_argument("--timeout", type=float, default=45.0)
    p.add_argument("--settle", type=float, default=4.0, help="seconds to let the UI come back")
    p = sub.add_parser("shot", help="type /fxdev shot, wait for the PNG, decode the beacon, write crops")
    p.add_argument("--timeout", type=float, default=20.0)
    p.add_argument("--file", help="decode an existing PNG instead (types nothing, cache untouched)")
    p = sub.add_parser("sv", help="SavedVariables as JSON (luajit, empty environment)")
    p.add_argument("which", choices=["core", "dev"])
    p.add_argument("--path", help="dotted selection, e.g. errors.list.-1 (Lua lists are 1-based)")
    sub.add_parser("errors", help="ForteXorcistDB.errors from the last flushed SavedVariables")
    p = sub.add_parser("selftest", help="type /fxdev selftest, poll shots until finished or timeout")
    p.add_argument("suite", nargs="?")
    p.add_argument("--force", action="store_true")
    p.add_argument("--timeout", type=float, default=60.0)
    p.add_argument("--poll", type=float, default=4.0)
    p = sub.add_parser("loop", help="ONE iteration: deploy, reload, selftest, shot, reload, read")
    p.add_argument("--suite")
    p.add_argument("--force", action="store_true")
    p.add_argument("--timeout", type=float, default=45.0, help="per-reload wait")
    p.add_argument("--settle", type=float, default=4.0)
    p.add_argument("--selftest-timeout", type=float, default=60.0)
    return ap


VERBS = {"status": v_status, "deploy": v_deploy, "type": v_type, "reload": v_reload,
         "shot": v_shot, "sv": v_sv, "errors": v_errors, "selftest": v_selftest, "loop": v_loop}


def emit(out, obj):
    out.write(json.dumps(obj, indent=2, ensure_ascii=False, default=str) + "\n")


def main(argv=None, ctx=None, out=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    out = out or sys.stdout
    ctx = ctx or Ctx()
    try:
        if argv and argv[0] == "commands" and not any(t in ("-h", "--help") for t in argv[1:]):
            result = v_commands(ctx, argv[1:])
        else:
            a = build_parser().parse_args(argv)
            if a.verb == "commands":
                result = v_commands(ctx, a.rest)
            else:
                result = VERBS[a.verb](ctx, a)
        emit(out, result)
        return 0
    except FxError as e:
        emit(out, {"ok": False, "error": str(e), "exit": e.code, **e.extra})
        return e.code
    except SystemExit as e:                       # argparse usage errors / --help
        return e.code if isinstance(e.code, int) else 2


if __name__ == "__main__":
    sys.exit(main())
