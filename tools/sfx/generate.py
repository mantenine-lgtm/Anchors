#!/usr/bin/env python3
"""ROFLY 효과음 만들기: sounds.json 의 문구로 ElevenLabs Sound Effects API 를 불러 mp3 를 저장합니다.

맥에서 (ElevenLabs 키는 ~/ROFLY/.env 의 ELEVENLABS_API_KEY, `elevenlabs onboard` 가 넣어 둔 것):
    python3 tools/sfx/generate.py --env-file ~/ROFLY/.env --out ~/Downloads/rofly-sounds/raw

- 소리마다 sounds.json 의 variants 개(기본 3안)를 만들고, 안마다 prompt_influence 를 바꿉니다.
- 이미 만든 파일은 건너뛰므로 중간에 멈춰도 다시 돌리면 이어서 만듭니다.
- 결과: <out>/<이름>_<안>.mp3 와 <out>/manifest.json (문구, 모델, 크레딧).
- 키는 화면이나 파일 어디에도 쓰지 않습니다. 파이썬 기본 모듈만 씁니다 (맥 기본 python3 로 실행).
- 만든 소리는 공개 저장소에 올리지 않습니다 (ElevenLabs 약관: 소리 파일만 따로 배포 금지, 게임 안에서 쓰는 것은 허용).
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
# 시험할 때만 ROFLY_ELEVEN_BASE 로 가짜 서버를 가리킴 (그때는 다시 시도할 때 기다리지 않음)
TEST_BASE = os.environ.get("ROFLY_ELEVEN_BASE", "")
BASE = TEST_BASE or "https://api.elevenlabs.io/v1"
RETRY_CODES = (408, 409, 425, 429, 500, 502, 503, 504)


def read_key(env_file):
    key = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    if key or not env_file:
        return key
    path = os.path.expanduser(env_file)
    if not os.path.exists(path):
        return ""
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line.startswith("export "):
                line = line[len("export "):].strip()
            if line.startswith("ELEVENLABS_API_KEY="):
                return line.split("=", 1)[1].strip().strip("'\"")
    return ""


def open_request(key, method, path, body=None, timeout=180):
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("xi-api-key", key)
    req.add_header("User-Agent", "rofly-sfx/1.0")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    return urllib.request.urlopen(req, timeout=timeout)


def error_text(err):
    try:
        raw = err.read().decode("utf-8", "replace")
    except Exception:
        raw = ""
    try:
        detail = json.loads(raw).get("detail")
        if isinstance(detail, dict):
            return "%s %s" % (detail.get("status", ""), detail.get("message", ""))
        if isinstance(detail, list) and detail:
            return "; ".join(str(d.get("msg", d)) if isinstance(d, dict) else str(d) for d in detail)
        if detail:
            return str(detail)
    except Exception:
        pass
    return raw[:300]


def subscription(key):
    try:
        with open_request(key, "GET", "/user/subscription", timeout=30) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return {"error": "%d %s" % (e.code, error_text(e))}
    except Exception as e:  # 네트워크 오류 등
        return {"error": str(e)}


def make_sound(key, sound, influence, model, fmt):
    body = {
        "text": sound["prompt"],
        "duration_seconds": sound["duration"],
        "prompt_influence": influence,
        "model_id": model,
    }
    if sound.get("loop"):
        body["loop"] = True
    with open_request(key, "POST", "/sound-generation?output_format=" + fmt, body) as r:
        return r.read(), r.headers.get("character-cost")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--env-file", default=".env", help="ELEVENLABS_API_KEY 가 든 .env (환경 변수가 있으면 그것을 씀)")
    ap.add_argument("--spec", default=os.path.join(HERE, "sounds.json"))
    ap.add_argument("--out", required=True, help="mp3 를 저장할 폴더")
    ap.add_argument("--only", default="", help="이 이름들만 (쉼표로 구분)")
    ap.add_argument("--variants", type=int, default=0, help="소리마다 만들 안 수 (기본: sounds.json)")
    ap.add_argument("--allow-free", action="store_true", help="무료 요금제여도 만듦 (상업적 이용 불가)")
    ap.add_argument("--dry-run", action="store_true", help="요금제·예상 크레딧만 보고 만들지 않음")
    args = ap.parse_args()

    key = read_key(args.env_file)
    if not key:
        sys.exit("ELEVENLABS_API_KEY 를 찾지 못했습니다 (환경 변수나 %s)" % args.env_file)

    with open(args.spec, encoding="utf-8") as f:
        spec = json.load(f)
    only = set(n for n in args.only.split(",") if n)
    sounds = [s for s in spec["sounds"] if not only or s["name"] in only]
    if only and len(sounds) != len(only):
        sys.exit("sounds.json 에 없는 이름: %s" % ", ".join(sorted(only - set(s["name"] for s in sounds))))
    variants = args.variants or spec["variants"]
    influences = spec["influence"]
    fmt = spec.get("outputFormat", "mp3_44100_128")
    out = os.path.expanduser(args.out)

    seconds = sum(s["duration"] for s in sounds) * variants
    print("소리 %d개 x %d안, 길이 합 %.1f초, 예상 %d 크레딧" % (len(sounds), variants, seconds, round(seconds * spec["creditsPerSecond"])))

    sub = subscription(key)
    if "error" in sub:
        print("요금제를 확인하지 못함 (키에 사용자 읽기 권한이 없으면 그럴 수 있음): " + sub["error"])
    else:
        left = (sub.get("character_limit") or 0) - (sub.get("character_count") or 0)
        print("요금제: %s, 이번 달 남은 크레딧: %s" % (sub.get("tier"), left))
        if str(sub.get("tier", "")).lower() == "free" and not args.allow_free:
            sys.exit("멈춤: 무료 요금제로 만든 소리는 상업적으로 쓸 수 없습니다 (그래도 만들려면 --allow-free)")
    if args.dry_run:
        return

    os.makedirs(out, exist_ok=True)
    manifest_path = os.path.join(out, "manifest.json")
    manifest = {"items": []}
    if os.path.exists(manifest_path):
        with open(manifest_path, encoding="utf-8") as f:
            manifest = json.load(f)
    have = {}
    for item in manifest["items"]:
        if os.path.exists(os.path.join(out, item["file"])):
            have[(item["name"], item["variant"])] = item
    manifest["items"] = list(have.values())

    def save():
        tmp = manifest_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=1)
        os.replace(tmp, manifest_path)

    made, failed, cost_total = 0, [], 0
    for sound in sounds:
        model = spec["model"]
        for variant in range(1, variants + 1):
            if (sound["name"], variant) in have:
                continue
            influence = influences[(variant - 1) % len(influences)]
            name = "%s_%d" % (sound["name"], variant)
            audio, cost, last_error = None, None, ""
            for attempt in range(6):
                try:
                    audio, cost = make_sound(key, sound, influence, model, fmt)
                    break
                except urllib.error.HTTPError as e:
                    last_error = "%d %s" % (e.code, error_text(e))
                    if e.code in (401, 403):
                        save()
                        sys.exit("키가 거절됨: " + last_error)
                    if e.code in (400, 422) and spec.get("fallbackModel") and model != spec["fallbackModel"]:
                        print("  %s: %s 가 거절함 (%s), %s 로 다시" % (name, model, last_error, spec["fallbackModel"]))
                        model = spec["fallbackModel"]
                        continue
                    if e.code not in RETRY_CODES:
                        break
                except Exception as e:  # 시간 초과, 연결 끊김
                    last_error = str(e)
                wait = 0 if TEST_BASE else min(60, 3 * 2 ** attempt)
                print("  %s: %s, %d초 뒤 다시" % (name, last_error, wait))
                time.sleep(wait)
            if audio is None:
                failed.append("%s (%s)" % (name, last_error))
                print("  실패 %s: %s" % (name, last_error))
                continue
            file = name + ".mp3"
            with open(os.path.join(out, file), "wb") as f:
                f.write(audio)
            try:
                cost_total += int(cost or 0)
            except ValueError:
                pass
            manifest["items"].append({
                "name": sound["name"], "variant": variant, "file": file, "model": model,
                "prompt": sound["prompt"], "duration": sound["duration"], "loop": bool(sound.get("loop")),
                "influence": influence, "bytes": len(audio), "cost": cost,
            })
            save()
            made += 1
            print("  %s: %d KB, %s, 크레딧 %s" % (file, len(audio) // 1024, model, cost))

    save()
    print("새로 만든 것 %d개, 쓴 크레딧 %d, 실패 %d개%s" % (made, cost_total, len(failed), (": " + ", ".join(failed)) if failed else ""))
    print("폴더: " + out)
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
