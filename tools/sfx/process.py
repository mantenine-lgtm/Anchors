#!/usr/bin/env python3
"""generate.py 가 만든 mp3 를 게임에 넣을 소리로 다듬습니다 (ffmpeg, numpy 필요).

    python3 tools/sfx/process.py <raw 폴더> <결과 폴더>

- 모두 모노 44.1 kHz 로 줄임 (용량을 줄이려고, 화면 소리라 좌우가 필요 없음).
- 짧은 소리: 앞 무음을 자르고, 뒤 무음·maxLength 넘는 부분을 자르며 끝을 부드럽게 줄임.
- 반복 소리(loop): 끝 0.4초를 처음 0.4초에 겹쳐 섞어(크로스페이드) 이음매에서 끊기거나 튀지 않게 함.
- 크기: 가장 큰 0.1초 구간의 세기를 소리 종류마다 같은 기준으로 맞추고, 최고점은 -1 dBFS 아래로.
- smallSpeaker (반복 소리): 노트북·폰 스피커는 150 Hz 아래를 거의 못 내므로, 낮은 소리의 배음을 만들어
  150~1500 Hz 에 섞고 35 Hz 아래는 덜어 냄 (심리 저음). 필터는 원형(FFT)이라 반복 이음매가 그대로 이어짐.
- 결과: <결과>/ogg/<이름>_<안>.ogg (Roblox 에 올릴 파일), <결과>/wav/... (들어 보기용), <결과>/report.json
"""

import json
import os
import subprocess
import sys

import numpy as np

RATE = 44100
PEAK_MAX = 10 ** (-1 / 20)  # -1 dBFS
ONESHOT_LOUD = 10 ** (-14 / 20)  # 짧은 소리: 가장 큰 0.1초 구간의 RMS
LOOP_LOUD = 10 ** (-17 / 20)  # 반복 소리: 전체 RMS
START_GATE = 10 ** (-45 / 20)
END_GATE = 10 ** (-52 / 20)
LOOP_XFADE = 0.4
OGG_QUALITY = "4"

HERE = os.path.dirname(os.path.abspath(__file__))


def decode(path):
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(RATE), "-f", "f32le", "-"],
        check=True, capture_output=True,
    ).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def encode_ogg(x, path):
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "-",
         "-c:a", "libvorbis", "-q:a", OGG_QUALITY, path],
        input=x.astype(np.float32).tobytes(), check=True,
    )


def write_wav(x, path):
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "-",
         "-c:a", "pcm_s16le", path],
        input=x.astype(np.float32).tobytes(), check=True,
    )


def db(v):
    return 20 * np.log10(max(float(v), 1e-9))


def frame_rms(x, seconds):
    n = max(1, int(RATE * seconds))
    if len(x) < n:
        return np.array([np.sqrt(np.mean(x ** 2))]) if len(x) else np.array([0.0])
    usable = len(x) // n * n
    return np.sqrt(np.mean(x[:usable].reshape(-1, n) ** 2, axis=1))


def max_window_rms(x, seconds=0.1):
    n = max(1, int(RATE * seconds))
    if len(x) <= n:
        return float(np.sqrt(np.mean(x ** 2)))
    c = np.concatenate([[0.0], np.cumsum(x ** 2)])
    return float(np.sqrt(np.max(c[n:] - c[:-n]) / n))


def centroid(x):
    if len(x) < 64:
        return 0.0
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    freqs = np.fft.rfftfreq(len(x), 1 / RATE)
    return float(np.sum(freqs * spec) / max(np.sum(spec), 1e-9))


def gain_to(x, loud, measured):
    peak = float(np.max(np.abs(x))) if len(x) else 0.0
    if peak <= 0 or measured <= 0:
        return x, 1.0
    g = min(loud / measured, PEAK_MAX / peak)
    return x * g, g


def oneshot(x, max_length):
    info = {}
    x = x - np.mean(x)
    above = np.nonzero(np.abs(x) > START_GATE)[0]
    if len(above) == 0:
        raise ValueError("소리가 거의 없음")
    start = max(0, above[0] - int(0.004 * RATE))
    env = frame_rms(x[start:], 0.01)
    loud = np.nonzero(env > END_GATE)[0]
    end = start + (loud[-1] + 1) * int(0.01 * RATE) if len(loud) else len(x)
    end = min(end, len(x))
    cut = False
    if max_length and (end - start) > int(max_length * RATE):
        end = start + int(max_length * RATE)
        cut = True
    y = x[start:end].copy()
    info["trimStartMs"] = round(start / RATE * 1000)
    info["cut"] = cut
    fade_in = min(int(0.002 * RATE), len(y) // 4)
    if fade_in > 0:
        y[:fade_in] *= np.linspace(0, 1, fade_in)
    fade_out = int(min(0.08 if cut else 0.04, 0.3 * len(y) / RATE) * RATE)
    if fade_out > 1:
        y[-fade_out:] *= np.cos(np.linspace(0, np.pi / 2, fade_out)) ** 2
    y, g = gain_to(y, ONESHOT_LOUD, max_window_rms(y))
    info["gainDb"] = round(db(g), 1)
    peak_at = int(np.argmax(np.abs(y)))
    info["peakAtMs"] = round(peak_at / RATE * 1000)
    return y, info


def fft_filter(x, gain):
    """위상을 바꾸지 않는 원형 필터. gain(주파수 배열) -> 배율."""
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / RATE)
    return np.fft.irfft(spec * gain(freqs), len(x))


def ramp(f, a, b):
    """주파수 a 아래 0, b 위 1 인 부드러운 계단 (가파른 필터용)."""
    t = np.clip((f - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def band_level(x, lo, hi):
    spec = np.abs(np.fft.rfft(x)) ** 2
    freqs = np.fft.rfftfreq(len(x), 1 / RATE)
    share = spec[(freqs >= lo) & (freqs < hi)].sum() / max(spec.sum(), 1e-12)
    return db(np.sqrt(np.mean(x ** 2) * share))


def rms(x):
    return float(np.sqrt(np.mean(x ** 2)))


SPEAKER_HARM_DB = -5  # 만든 배음을 원래 저음보다 이만큼 작게 섞음


def small_speaker(y):
    low = fft_filter(y, lambda f: 1 - ramp(f, 120, 170))  # 스피커가 못 내는 저음
    u = low / max(3 * rms(low), 1e-9)
    harm = np.tanh(4 * u) + 0.7 * (np.abs(u) - np.mean(np.abs(u)))  # 홀수·짝수 배음
    harm = fft_filter(harm, lambda f: ramp(f, 170, 240) * (1 - ramp(f, 1400, 2200)))  # 원래 저음은 빼고 배음만
    harm *= rms(low) / max(rms(harm), 1e-9) * 10 ** (SPEAKER_HARM_DB / 20)
    return fft_filter(y, lambda f: ramp(f, 25, 45)) + harm


def make_loop(x, speaker=False):
    info = {}
    x = x - np.mean(x)
    f = int(min(LOOP_XFADE, len(x) / RATE / 6) * RATE)
    head, tail = x[:f], x[len(x) - f:]
    t = np.linspace(0, np.pi / 2, f)
    y = x[: len(x) - f].copy()
    y[:f] = head * np.sin(t) + tail * np.cos(t)  # 이음매: 끝(tail)이 처음(head)으로 넘어감
    info["midDbBefore"] = round(band_level(y / max(float(np.sqrt(np.mean(y ** 2))), 1e-9) * LOOP_LOUD, 200, 4000), 1)
    if speaker:
        y = small_speaker(y)
    frames = frame_rms(y, 0.1)
    info["steadiness"] = round(float(np.std(frames) / max(np.mean(frames), 1e-9)), 3)  # 작을수록 고름
    y, g = gain_to(y, LOOP_LOUD, float(np.sqrt(np.mean(y ** 2))))
    info["gainDb"] = round(db(g), 1)
    local = float(np.sqrt(np.mean(np.concatenate([y[-441:], y[:441]]) ** 2)))
    info["seamJump"] = round(abs(float(y[-1] - y[0])) / max(local, 1e-9), 3)  # 이음매의 튐 (1 아래면 보통 소리 흐름 수준)
    info["midDb"] = round(band_level(y, 200, 4000), 1)  # 노트북·폰 스피커가 내는 대역의 세기
    return y, info


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    raw, out = sys.argv[1], sys.argv[2]
    with open(os.path.join(raw, "manifest.json"), encoding="utf-8") as fh:
        manifest = json.load(fh)
    spec_path = os.path.join(raw, "sounds.json")
    if not os.path.exists(spec_path):
        spec_path = os.path.join(HERE, "sounds.json")
    with open(spec_path, encoding="utf-8") as fh:
        spec = {s["name"]: s for s in json.load(fh)["sounds"]}
    os.makedirs(os.path.join(out, "ogg"), exist_ok=True)
    os.makedirs(os.path.join(out, "wav"), exist_ok=True)
    report = []
    for item in sorted(manifest["items"], key=lambda i: (list(spec).index(i["name"]) if i["name"] in spec else 99, i["variant"])):
        s = spec.get(item["name"], {})
        base = "%s_%d" % (item["name"], item["variant"])
        x = decode(os.path.join(raw, item["file"]))
        if s.get("loop") or item.get("loop"):
            y, info = make_loop(x, bool(s.get("smallSpeaker")))
            info["loop"] = True
        else:
            y, info = oneshot(x, s.get("maxLength"))
            info["loop"] = False
        ogg = os.path.join(out, "ogg", base + ".ogg")
        encode_ogg(y, ogg)
        write_wav(y, os.path.join(out, "wav", base + ".wav"))
        info.update({
            "name": item["name"], "variant": item["variant"], "model": item.get("model"), "influence": item.get("influence"),
            "sourceSeconds": round(len(x) / RATE, 2), "seconds": round(len(y) / RATE, 3),
            "oggBytes": os.path.getsize(ogg), "peakDb": round(db(np.max(np.abs(y))), 1),
            "rmsDb": round(db(np.sqrt(np.mean(y ** 2))), 1), "centroidHz": round(centroid(y)),
        })
        report.append(info)
        print("%-18s %5.2fs  %5.1f KB  peak %5.1f dB  rms %5.1f dB  %s" % (
            base, info["seconds"], info["oggBytes"] / 1024, info["peakDb"], info["rmsDb"],
            ("이음매 %.2f 고름 %.2f 중음 %.1f→%.1f dB" % (info["seamJump"], info["steadiness"], info["midDbBefore"], info["midDb"])) if info["loop"] else ("앞 %dms 자름%s" % (info["trimStartMs"], ", 길이 자름" if info["cut"] else ""))))
    with open(os.path.join(out, "report.json"), "w", encoding="utf-8") as fh:
        json.dump(report, fh, ensure_ascii=False, indent=1)
    total = sum(r["oggBytes"] for r in report)
    print("%d개, ogg 합계 %.0f KB" % (len(report), total / 1024))


if __name__ == "__main__":
    main()
