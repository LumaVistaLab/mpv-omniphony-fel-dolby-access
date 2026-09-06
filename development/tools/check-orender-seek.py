#!/usr/bin/env python3
"""Compare decoded PCM before/after repeated orender resets (requires NumPy).

Feed a raw E-AC-3 or TrueHD Atmos excerpt. Each reset replays the same packets,
so every audible channel must recover without accumulating a metadata delay.
No audio device is opened. The report is written to stdout as JSON.
"""

import argparse
import ctypes as C
import json
from pathlib import Path
import time

import numpy as np


class Config(C.Structure):
    _fields_ = [
        ("sample_rate", C.c_uint32),
        ("config_yaml_path", C.c_char_p),
        ("speaker_layout_path", C.c_char_p),
        ("bridge_path", C.c_char_p),
        ("codec", C.c_char_p),
        ("osc_enabled", C.c_int),
        ("osc_port_in", C.c_uint16),
        ("osc_port_out", C.c_uint16),
        ("osc_bind", C.c_char_p),
        ("osc_host", C.c_char_p),
    ]


def packets(data, codec):
    offset = 0
    while offset + 6 <= len(data):
        if codec == "eac3":
            if data[offset:offset + 2] != b"\x0b\x77":
                raise ValueError(f"Missing E-AC-3 sync at {offset}")
            if data[offset + 5] >> 3 <= 10:
                # Blu-ray E-AC-3 can interleave a legacy AC-3 core.
                rates = (32, 40, 48, 56, 64, 80, 96, 112, 128, 160,
                         192, 224, 256, 320, 384, 448, 512, 576, 640)
                fscod, code = data[offset + 4] >> 6, data[offset + 4] & 63
                if fscod > 2 or code >> 1 >= len(rates):
                    raise ValueError(f"Invalid AC-3 header at {offset}")
                rate = rates[code >> 1]
                words = (rate * 2, rate * 320 // 147 + (code & 1), rate * 3)
                size = 2 * words[fscod]
            else:
                size = 2 * (1 + ((data[offset + 2] & 7) << 8 | data[offset + 3]))
        else:
            size = 2 * ((data[offset] & 15) << 8 | data[offset + 1])
        if size < 4 or offset + size > len(data):
            raise ValueError(f"Invalid or truncated access unit at {offset}")
        yield data[offset:offset + size]
        offset += size
    if offset != len(data):
        raise ValueError("Trailing partial access unit")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sample", type=Path)
    parser.add_argument("--orender", required=True, type=Path)
    parser.add_argument("--bridge", required=True, type=Path)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--codec", choices=["eac3", "truehd"], default="eac3")
    parser.add_argument("--seconds", type=float, default=3)
    parser.add_argument("--resets", type=int, default=3)
    args = parser.parse_args()
    if args.seconds <= 0 or args.resets < 1:
        parser.error("seconds must be positive and resets must be at least one")

    lib = C.CDLL(str(args.orender.resolve()))
    lib.orender_create.argtypes = [C.POINTER(Config)]
    lib.orender_create.restype = C.c_void_p
    lib.orender_destroy.argtypes = [C.c_void_p]
    lib.orender_destroy.restype = None
    lib.orender_reset.argtypes = [C.c_void_p]
    lib.orender_reset.restype = None
    lib.orender_process.argtypes = [
        C.c_void_p, C.c_void_p, C.c_size_t, C.c_int64,
        C.POINTER(C.c_float), C.c_size_t, C.POINTER(C.c_size_t),
        C.POINTER(C.c_uint32), C.POINTER(C.c_int64),
    ]
    lib.orender_process.restype = C.c_int
    cfg = Config(
        sample_rate=48000,
        config_yaml_path=str(args.config.resolve()).encode("utf-8"),
        bridge_path=str(args.bridge.resolve()).encode("utf-8"),
        codec=args.codec.encode("ascii"),
    )
    encoded = list(packets(args.sample.read_bytes(), args.codec))
    handle = lib.orender_create(C.byref(cfg))
    if not handle:
        raise RuntimeError("orender_create failed")

    buf = np.empty(192000 * 32, dtype=np.float32)
    frames, channels, pts = C.c_size_t(), C.c_uint32(), C.c_int64()
    baseline = None
    reports = []
    passed = True
    try:
        for iteration in range(args.resets + 1):
            start = time.perf_counter()
            if iteration:
                # Also exercise a redundant reset with no intervening PCM.
                lib.orender_reset(handle)
                lib.orender_reset(handle)
            reset_ms = (time.perf_counter() - start) * 1000
            chunks = []
            total = 0
            first_pts = None
            for packet in encoded:
                rc = lib.orender_process(
                    handle, packet, len(packet), 0,
                    buf.ctypes.data_as(C.POINTER(C.c_float)), buf.size,
                    C.byref(frames), C.byref(channels), C.byref(pts),
                )
                if rc != 0:
                    raise RuntimeError(f"orender_process returned {rc}")
                if frames.value:
                    if first_pts is None:
                        first_pts = pts.value
                    chunks.append(buf[:frames.value * channels.value].copy().reshape(-1, channels.value))
                    total += frames.value
                if total >= args.seconds * 48000:
                    break
            if not chunks:
                raise RuntimeError("Sample produced no decoded PCM")
            pcm = np.concatenate(chunks)
            # Exclude only the first 100 ms of filter history after reset.
            stable = pcm[4800:]
            if stable.size == 0 or not np.isfinite(pcm).all():
                raise RuntimeError("Insufficient or non-finite PCM")
            rms = np.sqrt(np.mean(stable.astype(np.float64) ** 2, axis=0))
            nonzero = np.flatnonzero(np.max(np.abs(pcm), axis=1) > 1e-5)
            report = {
                "reset": iteration, "reset_ms": round(reset_ms, 3),
                "frames": len(pcm), "first_pts_us": first_pts,
                "first_audible_ms": round(float(nonzero[0]) / 48, 3) if len(nonzero) else None,
                "channel_rms": rms.tolist(),
            }
            if baseline is None:
                baseline = stable.copy()
                baseline_rms = rms
                baseline_onset = int(nonzero[0]) if len(nonzero) else None
                if np.max(rms) < 1e-4:
                    raise RuntimeError("Baseline is silent; choose an audible excerpt")
            else:
                active = baseline_rms > max(1e-5, np.max(baseline_rms) * 0.01)
                shape_ok = stable.shape == baseline.shape
                error = float(np.sqrt(np.mean((stable.astype(np.float64) - baseline) ** 2))) if shape_ok else float("inf")
                scale = float(np.sqrt(np.mean(baseline.astype(np.float64) ** 2)))
                report["relative_rms_error"] = error / max(scale, 1e-12)
                report["min_active_channel_ratio"] = float(np.min(rms[active] / baseline_rms[active]))
                onset_ok = bool(len(nonzero) and baseline_onset is not None
                                and nonzero[0] <= baseline_onset + 480)
                report["passed"] = bool(shape_ok and error < scale * 0.02
                                        and first_pts == 0 and onset_ok)
                passed &= report["passed"]
            reports.append(report)
    finally:
        lib.orender_destroy(handle)
    print(json.dumps({"sample": str(args.sample), "passed": passed, "runs": reports}, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
