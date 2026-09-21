#!/usr/bin/env python3
"""Validate Bilibili login and show a native QR login window when needed.

The QR payload is generated and rendered locally. Cookie values are never
printed. Only the smallest authentication-cookie subset that Bilibili accepts
as logged in is written to the persistent Netscape cookie file.
"""

from __future__ import annotations

import argparse
import copy
import http.cookiejar
import json
import os
from pathlib import Path
import queue
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request


REPO_ROOT = Path(__file__).resolve().parents[2]
GENERATE_URL = (
    "https://passport.bilibili.com/x/passport-login/web/qrcode/generate"
    "?source=main_web"
)
POLL_URL = "https://passport.bilibili.com/x/passport-login/web/qrcode/poll"
NAV_URL = "https://api.bilibili.com/x/web-interface/nav"
AUTH_COOKIE_ORDER = ("SESSDATA", "DedeUserID", "DedeUserID__ckMd5", "bili_jct")
USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/140.0.0.0 Safari/537.36"
)
EXIT_INVALID = 10
EXIT_CANCELLED = 11


def api_json(opener: urllib.request.OpenerDirector, url: str) -> dict:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json, text/plain, */*",
            "Referer": "https://www.bilibili.com/",
            "User-Agent": USER_AGENT,
        },
    )
    with opener.open(request, timeout=20) as response:
        return json.loads(response.read().decode("utf-8"))


def is_bilibili_domain(domain: str) -> bool:
    normalized = domain.lstrip(".").lower()
    return normalized == "bilibili.com" or normalized.endswith(".bilibili.com")


def cookie_map(jar: http.cookiejar.CookieJar) -> dict[str, http.cookiejar.Cookie]:
    result: dict[str, http.cookiejar.Cookie] = {}
    for cookie in jar:
        if cookie.name in AUTH_COOKIE_ORDER and is_bilibili_domain(cookie.domain):
            result[cookie.name] = cookie
    return result


def make_legacy_cookie(name: str, value: str) -> http.cookiejar.Cookie:
    return http.cookiejar.Cookie(
        version=0,
        name=name,
        value=value,
        port=None,
        port_specified=False,
        domain=".bilibili.com",
        domain_specified=True,
        domain_initial_dot=True,
        path="/",
        path_specified=True,
        secure=True,
        expires=None,
        discard=True,
        comment=None,
        comment_url=None,
        rest={"HttpOnly": None} if name == "SESSDATA" else {},
        rfc2109=False,
    )


def add_legacy_query_cookies(
    login_url: str, jar: http.cookiejar.CookieJar
) -> None:
    """Support old QR responses without decoding an encoded cookie value."""
    existing = cookie_map(jar)
    raw_query = urllib.parse.urlsplit(login_url).query
    for field in raw_query.split("&"):
        raw_name, separator, raw_value = field.partition("=")
        if not separator:
            continue
        name = urllib.parse.unquote(raw_name)
        if name in AUTH_COOKIE_ORDER and name not in existing:
            jar.set_cookie(make_legacy_cookie(name, raw_value))


def follow_login_ticket(
    opener: urllib.request.OpenerDirector,
    login_url: str,
    jar: http.cookiejar.CookieJar,
) -> None:
    """Exchange the current one-time cross-domain ticket for auth cookies."""
    if not login_url:
        raise RuntimeError("Bilibili returned an empty login ticket URL.")
    request = urllib.request.Request(
        login_url,
        headers={
            "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
            "Referer": "https://www.bilibili.com/",
            "User-Agent": USER_AGENT,
        },
    )
    with opener.open(request, timeout=25) as response:
        response.read()
        add_legacy_query_cookies(response.geturl(), jar)
    add_legacy_query_cookies(login_url, jar)


def select_cookie_jar(
    all_auth: dict[str, http.cookiejar.Cookie], names: tuple[str, ...]
) -> http.cookiejar.CookieJar:
    jar = http.cookiejar.CookieJar()
    for name in names:
        cookie = all_auth.get(name)
        if cookie is not None:
            jar.set_cookie(copy.copy(cookie))
    return jar


def load_netscape(path: Path) -> http.cookiejar.CookieJar:
    jar = http.cookiejar.MozillaCookieJar(str(path))
    if not path.is_file():
        return jar
    try:
        jar.load(ignore_discard=True, ignore_expires=True)
    except (OSError, http.cookiejar.LoadError) as exc:
        raise RuntimeError(f"Could not read the Bilibili cookie file: {exc}") from exc
    return jar


def login_status(jar: http.cookiejar.CookieJar) -> tuple[str, str]:
    """Return (valid|invalid|error, explanation) without exposing cookie data."""
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    try:
        payload = api_json(opener, NAV_URL)
    except (OSError, ValueError, urllib.error.URLError) as exc:
        return "error", f"Could not verify Bilibili login: {exc}"
    data = payload.get("data") or {}
    if payload.get("code") == 0 and data.get("isLogin") is True:
        return "valid", "Bilibili login is valid."
    return "invalid", "Bilibili login is missing or expired."


def save_netscape(jar: http.cookiejar.CookieJar, path: Path) -> None:
    output = http.cookiejar.MozillaCookieJar(str(path))
    for cookie in jar:
        output.set_cookie(copy.copy(cookie))
    output.save(ignore_discard=True, ignore_expires=True)


def choose_minimum_auth(
    all_auth: dict[str, http.cookiejar.Cookie],
) -> tuple[tuple[str, ...], http.cookiejar.CookieJar]:
    if "SESSDATA" not in all_auth:
        raise RuntimeError("Bilibili did not return SESSDATA.")

    available = tuple(name for name in AUTH_COOKIE_ORDER if name in all_auth)
    candidates = [("SESSDATA",)]
    if available != candidates[0]:
        candidates.append(available)

    last_error = None
    for names in candidates:
        candidate = select_cookie_jar(all_auth, names)
        status, explanation = login_status(candidate)
        if status == "valid":
            return names, candidate
        if status == "error":
            last_error = explanation

    if last_error:
        raise RuntimeError(last_error)
    raise RuntimeError("The returned Bilibili session did not validate as logged in.")


def write_cookie_file(
    auth: dict[str, http.cookiejar.Cookie], output_path: Path
) -> tuple[str, ...]:
    chosen_names, chosen_jar = choose_minimum_auth(auth)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_output = output_path.with_name(f".{output_path.name}.{os.getpid()}.tmp")
    try:
        save_netscape(chosen_jar, temporary_output)
        os.replace(temporary_output, output_path)
    finally:
        temporary_output.unlink(missing_ok=True)
    return chosen_names


def add_qrcode_search_paths() -> None:
    candidates = (
        REPO_ROOT / "distribution" / "tools" / "python-qrcode",
        REPO_ROOT / "build_temp" / "python-qrcode",
    )
    for candidate in candidates:
        if (candidate / "qrcode" / "__init__.py").is_file():
            sys.path.insert(0, str(candidate))


def login_worker(
    events: queue.Queue,
    stop_event: threading.Event,
    output_path: Path,
    poll_interval: float,
    deadline: float | None,
) -> None:
    def stopped() -> bool:
        return stop_event.is_set() or (
            deadline is not None and time.monotonic() >= deadline
        )

    def wait(seconds: float) -> bool:
        if deadline is not None:
            seconds = min(seconds, max(0.0, deadline - time.monotonic()))
        return stop_event.wait(seconds) or stopped()

    try:
        while not stopped():
            jar = http.cookiejar.CookieJar()
            opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
            try:
                generated = api_json(opener, GENERATE_URL)
                if generated.get("code") != 0:
                    raise RuntimeError("Bilibili rejected the QR-code request.")
                data = generated.get("data") or {}
                login_url = data["url"]
                qrcode_key = data["qrcode_key"]
            except (KeyError, OSError, RuntimeError, ValueError, urllib.error.URLError) as exc:
                events.put(("status", f"网络错误，5 秒后重试：{exc}", "#a33"))
                if wait(5.0):
                    break
                continue

            events.put(("qr", login_url))
            events.put(("status", "请使用哔哩哔哩 App 扫码", "#222"))
            last_state = None

            while not stopped():
                if wait(poll_interval):
                    break
                poll_query = urllib.parse.urlencode(
                    {"qrcode_key": qrcode_key, "source": "main_web"}
                )
                try:
                    polled = api_json(opener, f"{POLL_URL}?{poll_query}")
                except (OSError, ValueError, urllib.error.URLError) as exc:
                    events.put(("status", f"网络波动，正在重试：{exc}", "#a66"))
                    continue

                poll_data = polled.get("data") or {}
                state = poll_data.get("code")
                if state != last_state:
                    if state == 86101:
                        events.put(("status", "请使用哔哩哔哩 App 扫码", "#222"))
                    elif state == 86090:
                        events.put(("status", "已扫码，请在手机上确认登录", "#176b2c"))
                    elif state == 86038:
                        events.put(("status", "二维码已过期，正在自动刷新…", "#a66"))
                    elif state != 0:
                        events.put(("status", f"等待登录（状态 {state}）", "#a66"))
                    last_state = state

                if state == 86038:
                    break
                if state != 0:
                    continue

                events.put(("status", "登录已确认，正在保存…", "#176b2c"))
                success_url = poll_data.get("url") or ""
                follow_login_ticket(opener, success_url, jar)
                chosen_names = write_cookie_file(cookie_map(jar), output_path)
                events.put(("success", chosen_names))
                return

        if deadline is not None and time.monotonic() >= deadline:
            events.put(("failure", "登录等待超时，未修改 Cookie 文件。"))
        else:
            events.put(("cancelled",))
    except (KeyError, OSError, RuntimeError, ValueError, urllib.error.URLError) as exc:
        events.put(("failure", str(exc)))


def show_qr_login(
    output_path: Path, poll_interval: float, timeout: int
) -> tuple[int, tuple[str, ...]]:
    add_qrcode_search_paths()
    try:
        import qrcode
        import tkinter as tk
    except ImportError as exc:
        raise RuntimeError(
            "The local QR window dependency is missing. Run: "
            "powershell -ExecutionPolicy Bypass -File "
            "development\\scripts\\install-bilibili-login-helper.ps1"
        ) from exc

    try:
        root = tk.Tk()
    except tk.TclError as exc:
        raise RuntimeError(f"Could not open the Bilibili QR login window: {exc}") from exc

    events: queue.Queue = queue.Queue()
    stop_event = threading.Event()
    result = {"code": EXIT_CANCELLED, "names": ()}
    deadline = time.monotonic() + timeout if timeout > 0 else None

    root.title("哔哩哔哩扫码登录")
    root.configure(background="white")
    root.resizable(False, False)
    root.attributes("-topmost", True)

    heading = tk.Label(
        root,
        text="登录哔哩哔哩",
        font=("Microsoft YaHei UI", 17, "bold"),
        background="white",
        foreground="#111",
    )
    heading.pack(padx=30, pady=(22, 6))
    hint = tk.Label(
        root,
        text="打开哔哩哔哩 App，扫码并在手机上确认",
        font=("Microsoft YaHei UI", 10),
        background="white",
        foreground="#555",
    )
    hint.pack(padx=30, pady=(0, 12))
    canvas_size = 336
    canvas = tk.Canvas(
        root,
        width=canvas_size,
        height=canvas_size,
        background="white",
        highlightthickness=1,
        highlightbackground="#ddd",
    )
    canvas.pack(padx=28)
    status_var = tk.StringVar(value="正在生成二维码…")
    status = tk.Label(
        root,
        textvariable=status_var,
        font=("Microsoft YaHei UI", 10),
        background="white",
        foreground="#555",
        wraplength=390,
    )
    status.pack(padx=24, pady=(14, 10))

    def close_window() -> None:
        stop_event.set()
        root.destroy()

    close_button = tk.Button(
        root,
        text="取消",
        command=close_window,
        font=("Microsoft YaHei UI", 10),
        width=12,
    )
    close_button.pack(pady=(0, 20))
    root.protocol("WM_DELETE_WINDOW", close_window)

    def draw_qr(payload: str) -> None:
        qr = qrcode.QRCode(
            version=None,
            error_correction=qrcode.constants.ERROR_CORRECT_M,
            box_size=1,
            border=4,
        )
        qr.add_data(payload)
        qr.make(fit=True)
        matrix = qr.get_matrix()
        modules = len(matrix)
        cell = max(1, canvas_size // modules)
        drawn = cell * modules
        offset = (canvas_size - drawn) // 2
        canvas.delete("all")
        canvas.create_rectangle(0, 0, canvas_size, canvas_size, fill="white", outline="")
        for row_index, row in enumerate(matrix):
            for column_index, dark in enumerate(row):
                if not dark:
                    continue
                left = offset + column_index * cell
                top = offset + row_index * cell
                canvas.create_rectangle(
                    left,
                    top,
                    left + cell,
                    top + cell,
                    fill="black",
                    outline="black",
                )

    def drain_events() -> None:
        try:
            while True:
                event = events.get_nowait()
                kind = event[0]
                if kind == "qr":
                    draw_qr(event[1])
                elif kind == "status":
                    status_var.set(event[1])
                    status.configure(foreground=event[2])
                elif kind == "success":
                    result["code"] = 0
                    result["names"] = event[1]
                    status_var.set("登录成功，即将继续播放")
                    status.configure(foreground="#176b2c")
                    close_button.configure(state="disabled")
                    root.after(700, root.destroy)
                elif kind == "failure":
                    result["code"] = 1
                    status_var.set(event[1])
                    status.configure(foreground="#a33")
                    close_button.configure(text="关闭")
                    if timeout > 0:
                        root.after(1200, root.destroy)
                elif kind == "cancelled":
                    result["code"] = EXIT_CANCELLED
                    root.destroy()
        except queue.Empty:
            pass
        if root.winfo_exists():
            root.after(100, drain_events)

    worker = threading.Thread(
        target=login_worker,
        args=(events, stop_event, output_path, poll_interval, deadline),
        daemon=True,
        name="bilibili-qr-login",
    )
    worker.start()
    root.after(100, drain_events)
    root.after(900, lambda: root.attributes("-topmost", False))
    root.update_idletasks()
    width = root.winfo_width()
    height = root.winfo_height()
    left = max(0, (root.winfo_screenwidth() - width) // 2)
    top = max(0, (root.winfo_screenheight() - height) // 2)
    root.geometry(f"+{left}+{top}")
    root.mainloop()
    stop_event.set()
    return int(result["code"]), tuple(result["names"])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=REPO_ROOT / "bilibili-cookies.txt",
        help="Persistent Netscape cookie file.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Show a new QR login even if the existing cookie is valid.",
    )
    parser.add_argument(
        "--check-only",
        action="store_true",
        help=f"Validate without a popup; return {EXIT_INVALID} when logged out.",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=0,
        help="Overall login timeout in seconds; zero waits until cancelled.",
    )
    parser.add_argument("--poll-interval", type=float, default=2.0)
    args = parser.parse_args()

    if args.timeout < 0:
        parser.error("--timeout cannot be negative")
    if args.poll_interval < 1.0:
        parser.error("--poll-interval must be at least 1 second")

    output_path = args.output.resolve()
    if not args.force:
        try:
            existing = load_netscape(output_path)
            status, explanation = login_status(existing)
        except RuntimeError as exc:
            status, explanation = "invalid", str(exc)
        if status == "valid":
            print(explanation, flush=True)
            return 0
        if status == "error":
            print(f"ERROR: {explanation}", file=sys.stderr, flush=True)
            return 1
        if args.check_only:
            print(explanation, file=sys.stderr, flush=True)
            return EXIT_INVALID
        print(explanation, flush=True)
    elif args.check_only:
        parser.error("--force and --check-only cannot be used together")

    print("Opening the Bilibili QR login window...", flush=True)
    try:
        result, names = show_qr_login(
            output_path=output_path,
            poll_interval=args.poll_interval,
            timeout=args.timeout,
        )
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr, flush=True)
        return 1

    if result == 0:
        print(
            "Saved only the required Bilibili login cookie(s): " + ", ".join(names),
            flush=True,
        )
        print(f"COOKIE_FILE={output_path}", flush=True)
    elif result == EXIT_CANCELLED:
        print("Bilibili login was cancelled; no cookie file was changed.", flush=True)
    return result


if __name__ == "__main__":
    raise SystemExit(main())
