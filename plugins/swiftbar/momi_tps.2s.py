#!/usr/bin/env python3
# <xbar.title>momi - AI Token Speed</xbar.title>
# <xbar.version>v1.0</xbar.version>
# <xbar.author>momi</xbar.author>
# <xbar.desc>Real-time AI Token generation speed monitor</xbar.desc>

import datetime
import glob
import json
import os
import shlex

MAX_PLAUSIBLE_SPEED = 5000.0
TAIL_BYTES = 131072
END_STEP_TYPES = ("GENERIC", "MODEL", "TOOL", "CHECKPOINT", "ERROR_MESSAGE")


def parse_iso(raw):
    if not raw:
        return None
    try:
        return datetime.datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except Exception:
        return None


files = []
for rel in ("~/.gemini/antigravity/brain", "~/.gemini/antigravity-cli/brain"):
    brain_dir = os.path.expanduser(rel)
    for path in glob.glob(brain_dir + "/*/.system_generated/logs/transcript.jsonl"):
        try:
            if os.path.getsize(path) > 0:
                files.append(path)
        except OSError:
            pass

if not files:
    print("⚡ -- t/s")
    print("---")
    print("未找到活动会话日志")
    raise SystemExit(0)

newest_file = max(files, key=os.path.getmtime)
file_mod_time = os.path.getmtime(newest_file)
now_ts = datetime.datetime.now().timestamp()

try:
    with open(newest_file, "rb") as f:
        f.seek(0, os.SEEK_END)
        size = f.tell()
        f.seek(max(0, size - TAIL_BYTES))
        chunk = f.read().decode("utf-8", errors="ignore")
    raw_lines = [line.strip() for line in chunk.splitlines() if line.strip()]
    if len(raw_lines) > 1 and not raw_lines[0].startswith("{"):
        raw_lines = raw_lines[1:]
    steps = []
    for line in raw_lines:
        try:
            steps.append(json.loads(line))
        except Exception:
            pass
except Exception:
    print("⚡ -- t/s")
    raise SystemExit(0)

last_step = steps[-1] if steps else {}
last_type = last_step.get("type", "")
last_status = last_step.get("status", "")
in_flight = last_status == "RUNNING" or last_type in ("GENERIC", "USER_INPUT")
is_generating = (now_ts - file_mod_time) <= 900.0 and (in_flight or (now_ts - file_mod_time) < 2.5)

records = []
for i, step in enumerate(steps):
    if step.get("source") != "MODEL" or step.get("type") != "PLANNER_RESPONSE":
        continue
    out_tokens = step.get("output_tokens") or 0
    t_start = parse_iso(step.get("created_at"))
    if out_tokens <= 0 or not t_start:
        continue

    step_idx = step.get("step_index", i)
    if i + 1 < len(steps):
        next_step = steps[i + 1]
        if next_step.get("type") in END_STEP_TYPES:
            t_end = parse_iso(next_step.get("created_at"))
            if t_end and t_end >= t_start:
                dur = max(0.5, (t_end - t_start).total_seconds())
                tps = min(out_tokens / dur, MAX_PLAUSIBLE_SPEED)
                records.append((step_idx, out_tokens, dur, tps))
    elif (now_ts - file_mod_time) <= 15.0:
        mod_dt = datetime.datetime.fromtimestamp(file_mod_time, tz=datetime.timezone.utc)
        if mod_dt >= t_start:
            dur = max(0.5, (mod_dt - t_start).total_seconds())
            tps = min(out_tokens / dur, MAX_PLAUSIBLE_SPEED)
            records.append((step_idx, out_tokens, dur, tps))

if is_generating:
    if last_type == "USER_INPUT" or not records:
        print("⚡ 生成中 | color=#FF9500")
    else:
        print(f"⚡ {records[-1][3]:.1f} t/s | color=#FF9500")
else:
    print("⚡ -- t/s")

print("---")
print("⚡ momi · AI 实时测速仪 | size=14 bold=true")
if records:
    last = records[-1]
    print(f"最近速度: {last[3]:.1f} tok/s | color=#30D158 bold=true")
    print(f"上次耗时: {last[2]:.1f}s · {last[1]} tokens")
    print(f"会话 ID: {os.path.basename(os.path.dirname(os.path.dirname(os.path.dirname(newest_file))))}")
    print("---")
    print("📊 最近生成记录:")
    for r in list(reversed(records[-5:])):
        print(f"  • {r[1]} tok · {r[2]:.1f}s → {r[3]:.1f} tok/s | font=Menlo size=11")
else:
    print("暂无已完成的生成记录")

print("---")
print("🔄 刷新 | refresh=true")
log_dir = shlex.quote(os.path.dirname(newest_file))
print(f"📂 打开日志目录 | bash=/usr/bin/open param1={log_dir} terminal=false")
