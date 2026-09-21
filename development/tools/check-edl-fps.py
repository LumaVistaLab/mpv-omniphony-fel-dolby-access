"""Check fractional EDL frame rates through mpv's native format selector.

Usage: python development/tools/check-edl-fps.py path/to/mpv.com
Creates only temporary local media under build_temp; needs no network or login.
"""

import argparse
import json
import math
from pathlib import Path
import subprocess
import uuid
import wave


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mpv", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    probe = root / "development/tools/inspect-format-menu/console.lua"
    mpv = args.mpv.resolve()
    common = [str(mpv), "--no-config", "--vo=null", "--ao=null", "--aid=no",
              "--pause", "--ytdl=no", "--load-scripts=no", "--load-console=no",
              "--msg-level=all=error,console=info"]

    def run(url, inspect=True):
        options = [f"--script={probe}"] if inspect else ["--frames=0"]
        return subprocess.run(common + options + [url], capture_output=True,
                              encoding="utf-8", errors="replace", timeout=30)

    # Use ordinary inherited workspace permissions, including in Windows sandboxes.
    tmp = root / "build_temp" / ("edl-fps-" + uuid.uuid4().hex)
    tmp.mkdir()
    video, audio = tmp / "video.y4m", tmp / "audio.wav"
    try:
        video.write_bytes(b"YUV4MPEG2 W16 H16 F60000:1001 Ip A1:1 C420jpeg\n"
                          + (b"FRAME\n" + bytes([128]) * 384) * 4)
        with wave.open(str(audio), "wb") as output:
            output.setparams((1, 2, 48000, 0, "NONE", "not compressed"))
            output.writeframes(bytes(960))

        def escape(path):
            value = path.as_posix()
            return f"%{len(value.encode('utf-8'))}%{value},length=1"

        control = ("!new_stream;!no_clip;!no_chapters;"
                   "!track_meta,title=Opened,fps=59.94,flags=default;" + escape(video))
        container_only = ("!new_stream;!no_clip;!no_chapters;"
                          "!track_meta,title=Container-only;" + escape(video))

        def hint(label, value):
            fps = "" if value is None else ",fps=" + value
            return ("!new_stream;!no_clip;!no_chapters;"
                    "!delay_open,media_type=video,codec=rawvideo,w=16,h=16"
                    + fps + ";!track_meta,title=" + label + fps + ";" + escape(video))

        cases = [("integer", "60", 60), ("ntsc60", "59.94", 59.94),
                 ("source59", "59.93", 59.93), ("ntsc30", "29.97", 29.97),
                 ("film", "23.976", 23.976), ("exponent", "2.3976e1", 23.976),
                 ("zero", "0", None), ("missing", None, None)]
        parts = [control, container_only] + [hint(label, value) for label, value, _ in cases]
        parts.append("!new_stream;!no_clip;!no_chapters;"
                     "!delay_open,media_type=audio,codec=pcm_s16le;"
                     "!track_meta,title=Audio;" + escape(audio))
        result = run("edl://" + ";".join(parts))
        assert result.returncode == 0, result.stdout + result.stderr
        data = json.loads(next(line.split("FORMAT_MENU=", 1)[1]
                               for line in result.stdout.splitlines()
                               if "FORMAT_MENU=" in line))
        tracks = {track["title"]: track for track in data["tracks"]}
        assert math.isclose(tracks["Opened"]["demux_fps"], 60000 / 1001,
                            abs_tol=1e-6)
        assert tracks["Opened"]["format_fps"] == 59.94
        opened_label = next(item for item in data["video"] if " Opened (" in item)
        assert "59.94 fps" in opened_label and "59.9401 fps" not in opened_label
        assert tracks["Container-only"].get("format_fps") is None
        fallback_label = next(item for item in data["video"] if " Container-only (" in item)
        assert "59.9401 fps" in fallback_label
        for label, _, expected in cases:
            actual = tracks[label].get("demux_fps")
            if expected is None:
                assert actual is None, (label, actual)
            else:
                assert math.isclose(actual, expected, abs_tol=1e-9), (label, actual)
                assert math.isclose(tracks[label]["format_fps"], expected, abs_tol=1e-9)
                text = next(item for item in data["video"] if f" {label} (" in item)
                assert f"{expected:g} fps" in text, text

        for value in ["nan", "inf", "-inf", "1e999", "59.94junk", ""]:
            result = run("edl://" + control + ";" + hint("invalid", value), False)
            assert result.returncode != 0, f"Accepted invalid fps={value!r}"
            assert "Invalid number for fps" in result.stdout + result.stderr
    finally:
        video.unlink(missing_ok=True)
        audio.unlink(missing_ok=True)
        tmp.rmdir()

    print("PASS: stable advertised FPS for opened and delayed streams, "
          "container-only fallback, unchanged decoder FPS, "
          "and malformed/nonfinite FPS rejection")


if __name__ == "__main__":
    main()
