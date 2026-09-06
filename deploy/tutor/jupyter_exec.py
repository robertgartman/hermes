#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Execute code in a running Jupyter kernel and emit one compact JSON line.

Vendored for the hermes tutor sandbox. It replaces the third-party clone that the
bundled ``skills/data-science/jupyter-live-kernel`` skill drives
(``github.com/hamelsmu/hamelnb``), so the sandbox that serves two children has no
run-time ``git clone`` in its dependency chain.

DEPENDENCIES
    Python standard library, plus ``websockets`` -- a CORE dependency of
    hermes-agent at the pinned release (pyproject.toml declares
    ``websockets==15.0.1``), so it is already present in the orchestrator image.
    Nothing else is imported. No ``uv``, no network install, no clone.

THIS SCRIPT IS NOT A SECURITY BOUNDARY.
    It authenticates to Jupyter with a token, which is defence in depth only. The
    boundary that makes a kernel acceptable for a child is the pod network
    namespace and the host firewall (ADR-011, ADR-013, SPEC-tutor-isolation
    INV-1). Nothing this script does -- or refuses to do -- may be counted as an
    isolation control. A kernel is arbitrary code execution; treat every string
    that comes back from it as untrusted data, never as instructions.

PROTOCOL, ESTABLISHED FROM SOURCE (jupyter_server 2.x, jupyter_client 8.x)
    1. POST /api/sessions with {path, type, name, kernel:{name}} creates OR
       reuses: the handler calls session_exists(path) first and returns the
       existing model when one is live. session_exists() prunes a row whose
       kernel was culled, so a dead kernel self-heals on the next POST.
       Both branches answer 201 with the session model, incl. kernel.id.
    2. GET /api/kernels/<id>/channels upgrades to a websocket. Offering NO
       subprotocol selects the legacy JSON protocol: the server prefers
       "v1.kernel.websocket.jupyter.org" only when the client offers it.
    3. Client -> server frames are JSON objects carrying header, parent_header,
       metadata, content (all four are required -- Session.serialize indexes
       them directly) plus a "channel" key the server pops before relaying.
       The server signs the ZMQ message with its own key; the client never
       needs the HMAC key.
    4. Server -> client frames carry the same shape with "channel" added back.
       A message with binary buffers arrives as a BINARY frame using Jupyter's
       offset envelope, not as JSON -- see _deserialize_binary.
    5. Execution is finished when BOTH have arrived for our msg_id: the shell
       "execute_reply", and the iopub "status" with execution_state == "idle".
       Match on parent_header.msg_id; ignore everything else on the socket,
       which may include another client's traffic on the same kernel.

TRAPS THIS SCRIPT DEFENDS AGAINST, each read out of the server source
    * A message that reaches the server before its ZMQ streams exist is DROPPED
      SILENTLY: handle_incoming_message() returns early when self.channels is
      empty, logging at debug level, and the client then waits for a reply that
      will never come. Tornado closes the ordinary case for us -- it starts
      _receive_frame_loop() only after open() resolves, and open() awaits
      connect(), which creates the streams and attaches the iopub subscription
      (measured: an execute_request sent on the first frame after the 101 is
      answered normally). But connect() also has a failure branch that calls
      disconnect() and returns while the socket stays open, which leaves
      self.channels empty and every later send silently discarded. The
      kernel_info_request barrier below turns that hang into a clean transport
      error inside --connect-timeout, and doubles as a readiness probe.
    * A repeated session_id EVICTS the other client. _register_session() closes
      any open connection with the same "<kernel_id>:<session_id>" key, so a
      fixed session id would silently kick the student's JupyterLab tab off its
      own kernel. A fresh UUID is generated per invocation.
    * iopub output is rate limited by default (1000 msg/s, 1e6 bytes/s over a
      3 s window). Past the limit the server DROPS messages after injecting one
      stderr warning, so output can be incomplete without any error. The
      warning text is preserved in the stderr field rather than suppressed.
    * An Origin header must equal Host or the upgrade is refused; sending none
      is accepted ("assume from script"). We send none.
    * A WRONG token on a POST reports the wrong problem. check_xsrf_cookie()
      is bypassed only for token-authenticated requests, so a bad token falls
      through to the XSRF check and the server answers
      403 {"message": "'_xsrf' argument missing from POST"} -- no mention of
      the token at all. Measured, not reasoned. _request() therefore rewrites
      that specific 403 to name the likely cause, because chasing XSRF when the
      real fault is a stale token file costs an afternoon.
    * The token is read from JUPYTER_TOKEN / JUPYTER_TOKEN_FILE -- the same two
      variables the server itself reads -- and never from argv, so it does not
      appear in ps output or shell history.
    * JUPYTER_TOKEN_FILE may hold EITHER a bare token OR a systemd-style env
      file (`JUPYTER_TOKEN=...`). This deployment's credential is the latter
      (CONTRACT-tutor-sandbox names /etc/hermes-tutor/jupyter-token.env), and
      a reader that strips the whole file would send the literal string
      "JUPYTER_TOKEN=..." as the token -- which fails as the XSRF error above,
      i.e. two misleading errors stacked. resolve_token() parses both shapes.

EXIT CODES
    0    executed, kernel reported status "ok"
    1    executed, kernel reported "error" or "aborted"
    2    usage or configuration error (no token, bad arguments, missing dep)
    3    transport error (HTTP or websocket failure)
    124  timed out waiting for the kernel; an interrupt was requested
"""

from __future__ import annotations

import argparse
import json
import os
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timezone

PROTOCOL_VERSION = "5.3"
USERNAME = "hermes-tutor"
DEFAULT_URL = "http://127.0.0.1:8888"

EXIT_OK = 0
EXIT_KERNEL_ERROR = 1
EXIT_USAGE = 2
EXIT_TRANSPORT = 3
EXIT_TIMEOUT = 124


class UsageError(Exception):
    """Bad arguments or missing configuration."""


class TransportError(Exception):
    """HTTP or websocket failure."""


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #


def _iso_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _clip(text: str, limit: int):
    """Return (text, truncated). limit <= 0 means unlimited."""
    if limit > 0 and len(text) > limit:
        return text[:limit] + "\n...[truncated %d chars]" % (len(text) - limit), True
    return text, False


def _parse_token_file(text: str) -> str:
    """Accept either a bare token or a systemd-style env file.

    This deployment stores the credential as /etc/hermes-tutor/jupyter-token.env
    (CONTRACT-tutor-sandbox), which is an ENV FILE. Reading it whole and
    stripping would yield the literal "JUPYTER_TOKEN=<value>" and the server
    would then answer with the XSRF misdirection below -- a wrong credential
    reported as a wrong problem. Parse both shapes instead of assuming one.
    """
    bare = None
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export "):].strip()
        key, sep, value = line.partition("=")
        if sep:
            key = key.strip()
            value = value.strip().strip("'\"")
            if key in ("JUPYTER_TOKEN", "JUPYTER_SERVER_TOKEN") and value:
                return value
            continue
        if bare is None:
            bare = line
    return bare or ""


def resolve_token() -> str:
    """Read the Jupyter token from the environment. Never from argv."""
    token = os.environ.get("JUPYTER_TOKEN")
    if token and token.strip():
        return token.strip()
    path = os.environ.get("JUPYTER_TOKEN_FILE")
    if path:
        try:
            with open(path, encoding="utf-8") as handle:
                token = _parse_token_file(handle.read())
        except OSError as exc:
            raise UsageError("JUPYTER_TOKEN_FILE is unreadable: %s" % exc) from exc
        if token:
            return token
        raise UsageError(
            "JUPYTER_TOKEN_FILE holds no token: %s. Expected either a bare "
            "token or a line 'JUPYTER_TOKEN=<value>'." % path
        )
    raise UsageError(
        "no Jupyter token. Set JUPYTER_TOKEN or JUPYTER_TOKEN_FILE. "
        "The token is deliberately not accepted as a command-line argument."
    )


# --------------------------------------------------------------------------- #
# REST
# --------------------------------------------------------------------------- #


def _request(base_url: str, token: str, method: str, path: str, body, timeout: float):
    url = base_url.rstrip("/") + path
    headers = {"Authorization": "token " + token, "Accept": "application/json"}
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    # Empty ProxyHandler: never route a loopback call through an inherited
    # http_proxy/ALL_PROXY, which a container environment may well set.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(request, timeout=timeout) as response:
            raw = response.read()
            payload = json.loads(raw.decode("utf-8")) if raw else None
            return response.status, payload
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")[:500]
        if exc.code == 403 and "_xsrf" in detail:
            # Not an XSRF problem. check_xsrf_cookie() is bypassed only for
            # token-authenticated requests, so this is what a WRONG token looks
            # like on a POST. Say so, or the next reader debugs the wrong thing.
            detail += (
                "  [this is what an INVALID Jupyter token looks like on a POST:"
                " the XSRF bypass applies only to token-authenticated requests."
                " Check JUPYTER_TOKEN / JUPYTER_TOKEN_FILE.]"
            )
        raise TransportError("%s %s -> HTTP %d: %s" % (method, path, exc.code, detail)) from exc
    except urllib.error.URLError as exc:
        raise TransportError("%s %s -> %s" % (method, path, exc.reason)) from exc
    except (ValueError, OSError) as exc:
        raise TransportError("%s %s -> %s" % (method, path, exc)) from exc


def ensure_session(base_url: str, token: str, path: str, kernel_name: str, timeout: float):
    """Create or reuse the session for `path`. One POST does both."""
    body = {
        "path": path,
        "type": "notebook",
        "name": os.path.basename(path) or path,
        "kernel": {"name": kernel_name},
    }
    status, model = _request(base_url, token, "POST", "/api/sessions", body, timeout)
    if not isinstance(model, dict) or not (model.get("kernel") or {}).get("id"):
        raise TransportError(
            "POST /api/sessions returned %s without a kernel id: %r" % (status, model)
        )
    return model


def interrupt_kernel(base_url: str, token: str, kernel_id: str, timeout: float) -> bool:
    try:
        _request(
            base_url, token, "POST", "/api/kernels/%s/interrupt" % kernel_id, {}, timeout
        )
        return True
    except TransportError:
        return False


# --------------------------------------------------------------------------- #
# websocket
# --------------------------------------------------------------------------- #


def _ws_url(base_url: str, kernel_id: str, session_id: str) -> str:
    parts = urllib.parse.urlsplit(base_url)
    scheme = "wss" if parts.scheme == "https" else "ws"
    prefix = parts.path.rstrip("/")
    query = urllib.parse.urlencode({"session_id": session_id})
    return "%s://%s%s/api/kernels/%s/channels?%s" % (
        scheme,
        parts.netloc,
        prefix,
        urllib.parse.quote(kernel_id),
        query,
    )


def _connect(url: str, token: str, open_timeout: float):
    try:
        import inspect

        from websockets.sync.client import connect as ws_connect
    except ImportError as exc:
        raise UsageError(
            "the `websockets` package is not importable by %s. It is a core "
            "hermes-agent dependency; run this script with the interpreter that "
            "has the hermes-agent environment. (%s)" % (sys.executable, exc)
        ) from exc

    params = inspect.signature(ws_connect).parameters
    kwargs = {
        "open_timeout": open_timeout,
        "close_timeout": 5,
        # A single output frame can be large; the server already rate limits.
        "max_size": None,
        "compression": None,
        # Deliberately NO `subprotocols`: offering none selects the legacy JSON
        # protocol, so every frame is plain JSON we can parse without
        # jupyter_client. Deliberately NO `origin`: an Origin that does not
        # equal Host is refused, while none at all is accepted.
    }
    headers = {"Authorization": "token " + token}
    if "additional_headers" in params:
        kwargs["additional_headers"] = headers
    elif "extra_headers" in params:  # websockets < 14
        kwargs["extra_headers"] = headers
    else:
        raise UsageError("this `websockets` build accepts no custom headers")
    if "proxy" in params:  # websockets >= 14.2 defaults to the system proxy
        kwargs["proxy"] = None
    try:
        return ws_connect(url, **kwargs)
    except Exception as exc:  # noqa: BLE001 - handshake failures are many-shaped
        raise TransportError("websocket handshake failed: %s: %s" % (type(exc).__name__, exc)) from exc


def _deserialize_binary(blob: bytes):
    """Decode Jupyter's binary websocket envelope (message + buffers)."""
    if len(blob) < 8:
        raise TransportError("binary websocket frame too short (%d bytes)" % len(blob))
    nbufs = struct.unpack("!i", blob[:4])[0]
    if nbufs < 1 or len(blob) < 4 * (nbufs + 1):
        # serialize_binary_message() only emits this envelope when buffers
        # exist, so nbufs is >= 2 in practice. Fail loudly rather than
        # IndexError deep inside the receive loop.
        raise TransportError("malformed binary websocket frame (nbufs=%d)" % nbufs)
    offsets = list(struct.unpack("!" + "I" * nbufs, blob[4 : 4 * (nbufs + 1)]))
    offsets.append(None)
    message = json.loads(blob[offsets[0] : offsets[1]].decode("utf-8"))
    message["buffers"] = []
    message["_dropped_buffers"] = max(nbufs - 1, 0)
    return message


def _decode_frame(raw):
    if isinstance(raw, (bytes, bytearray)):
        return _deserialize_binary(bytes(raw))
    return json.loads(raw)


def _wire(session_id: str, msg_type: str, content: dict, channel: str):
    msg_id = uuid.uuid4().hex
    message = {
        "header": {
            "msg_id": msg_id,
            "session": session_id,
            "username": USERNAME,
            "date": _iso_now(),
            "msg_type": msg_type,
            "version": PROTOCOL_VERSION,
        },
        "parent_header": {},
        "metadata": {},
        "content": content,
        "buffers": [],
        "channel": channel,
    }
    return msg_id, message


def await_channels(ws, session_id: str, deadline: float, probe_every: float = 0.5):
    """Block until the kernel answers, proving the server's streams are live.

    Tornado already defers frame delivery until open() has built the ZMQ
    streams, so this is not needed for an ordinary connect. It exists for the
    branch where connect() fails after the handshake: self.channels stays empty
    and handle_incoming_message() then discards every send with only a debug
    log, which would otherwise present as a hang until --timeout. A
    kernel_info_reply is proof the shell stream round-trips.
    """
    next_probe = 0.0
    while True:
        now = time.monotonic()
        if now >= deadline:
            raise TransportError(
                "kernel did not answer kernel_info_request before the connect deadline"
            )
        if now >= next_probe:
            _, message = _wire(session_id, "kernel_info_request", {}, "shell")
            ws.send(json.dumps(message))
            next_probe = now + probe_every
        try:
            raw = ws.recv(timeout=min(probe_every, max(deadline - now, 0.01)))
        except TimeoutError:
            continue
        except Exception as exc:  # noqa: BLE001
            raise TransportError("websocket closed during handshake: %s" % exc) from exc
        frame = _decode_frame(raw)
        if (frame.get("header") or {}).get("msg_type") == "kernel_info_reply":
            return frame.get("content") or {}


# --------------------------------------------------------------------------- #
# execution
# --------------------------------------------------------------------------- #


class Collector:
    """Accumulates one execution's output, honouring clear_output."""

    def __init__(self, max_chars: int):
        self.max_chars = max_chars
        self.hard_cap = max_chars * 4 if max_chars > 0 else 0
        self.stdout: list = []
        self.stderr: list = []
        self.results: list = []
        self.display: list = []
        self.error = None
        self.execution_count = None
        self.truncated = False
        self.dropped_buffers = 0
        self.stdin_blocked = False
        self._pending_clear = False
        self._stdout_len = 0
        self._stderr_len = 0

    def _clear_now(self):
        self.stdout = []
        self.stderr = []
        self.results = []
        self.display = []
        self._stdout_len = 0
        self._stderr_len = 0
        self._pending_clear = False

    def _before_output(self):
        if self._pending_clear:
            self._clear_now()

    def stream(self, name: str, text: str):
        self._before_output()
        if name == "stderr":
            if self.hard_cap and self._stderr_len >= self.hard_cap:
                self.truncated = True
                return
            self.stderr.append(text)
            self._stderr_len += len(text)
        else:
            if self.hard_cap and self._stdout_len >= self.hard_cap:
                self.truncated = True
                return
            self.stdout.append(text)
            self._stdout_len += len(text)

    def bundle(self, data: dict, metadata: dict, execution_count=None):
        self._before_output()
        item = {}
        if execution_count is not None:
            item["execution_count"] = execution_count
        plain = data.get("text/plain")
        if isinstance(plain, str):
            item["text"], clipped = _clip(plain, self.max_chars)
            self.truncated = self.truncated or clipped
        others = sorted(k for k in data if k != "text/plain")
        if others:
            item["mime_types"] = others
            item["mime_sizes"] = {
                k: len(data[k]) if isinstance(data[k], str) else None for k in others
            }
        if metadata:
            item["has_metadata"] = True
        return item

    def finish(self):
        stdout, clipped_out = _clip("".join(self.stdout), self.max_chars)
        stderr, clipped_err = _clip("".join(self.stderr), self.max_chars)
        self.truncated = self.truncated or clipped_out or clipped_err
        return stdout, stderr


def execute(ws, session_id: str, code: str, deadline: float, collector: Collector,
            silent: bool, store_history: bool):
    """Send one execute_request and gather its output. Returns (status, msg_id)."""
    content = {
        "code": code,
        "silent": bool(silent),
        # silent=True forces store_history False kernel-side; mirror it here.
        "store_history": bool(store_history) and not silent,
        "user_expressions": {},
        # False so a stray input() raises in the kernel instead of hanging us.
        "allow_stdin": False,
        "stop_on_error": True,
    }
    msg_id, message = _wire(session_id, "execute_request", content, "shell")
    ws.send(json.dumps(message))

    reply_status = None
    got_reply = False
    got_idle = False

    while not (got_reply and got_idle):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return "timeout", msg_id
        try:
            raw = ws.recv(timeout=remaining)
        except TimeoutError:
            return "timeout", msg_id
        except Exception as exc:  # noqa: BLE001 - ConnectionClosed and friends
            raise TransportError("websocket closed during execution: %s" % exc) from exc

        frame = _decode_frame(raw)
        collector.dropped_buffers += frame.get("_dropped_buffers", 0)
        header = frame.get("header") or {}
        parent = (frame.get("parent_header") or {}).get("msg_id")
        if parent != msg_id:
            # Another client's traffic on the same kernel, or the tail of a
            # previous execution. Not ours.
            continue

        msg_type = header.get("msg_type")
        channel = frame.get("channel")
        body = frame.get("content") or {}

        if channel == "iopub":
            if msg_type == "stream":
                collector.stream(body.get("name", "stdout"), body.get("text", ""))
            elif msg_type == "execute_result":
                collector.results.append(
                    collector.bundle(
                        body.get("data") or {},
                        body.get("metadata") or {},
                        body.get("execution_count"),
                    )
                )
                collector.execution_count = body.get("execution_count", collector.execution_count)
            elif msg_type == "display_data" or msg_type == "update_display_data":
                collector.display.append(
                    collector.bundle(body.get("data") or {}, body.get("metadata") or {})
                )
            elif msg_type == "error":
                collector.error = {
                    "ename": body.get("ename"),
                    "evalue": body.get("evalue"),
                    "traceback": body.get("traceback") or [],
                }
            elif msg_type == "execute_input":
                collector.execution_count = body.get(
                    "execution_count", collector.execution_count
                )
            elif msg_type == "clear_output":
                if body.get("wait"):
                    collector._pending_clear = True
                else:
                    collector._clear_now()
            elif msg_type == "status":
                if body.get("execution_state") == "idle":
                    got_idle = True
        elif channel == "shell":
            if msg_type == "execute_reply":
                got_reply = True
                reply_status = body.get("status")
                if body.get("execution_count") is not None:
                    collector.execution_count = body["execution_count"]
                if reply_status == "error" and collector.error is None:
                    collector.error = {
                        "ename": body.get("ename"),
                        "evalue": body.get("evalue"),
                        "traceback": body.get("traceback") or [],
                    }
        elif channel == "stdin":
            # allow_stdin is False, so this should never happen. Answer it
            # rather than deadlock, and say so in the result.
            if msg_type == "input_request":
                collector.stdin_blocked = True
                _, reply = _wire(session_id, "input_reply", {"value": ""}, "stdin")
                reply["parent_header"] = header
                ws.send(json.dumps(reply))

    return reply_status or "ok", msg_id


# --------------------------------------------------------------------------- #
# entry point
# --------------------------------------------------------------------------- #


def _read_code(args) -> str:
    if args.code is not None:
        return args.code
    if args.code_file:
        if args.code_file == "-":
            return sys.stdin.read()
        try:
            with open(args.code_file, encoding="utf-8") as handle:
                return handle.read()
        except OSError as exc:
            raise UsageError("cannot read --code-file: %s" % exc) from exc
    if args.stdin:
        return sys.stdin.read()
    raise UsageError("one of --code, --code-file or --stdin is required")


def _emit(payload: dict) -> None:
    sys.stdout.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="jupyter_exec.py",
        description="Execute code in a running Jupyter kernel; print compact JSON.",
    )
    parser.add_argument("--path", required=True,
                        help="notebook path relative to the Jupyter root, e.g. work/scratch.ipynb")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--code", help="code to execute (prefer --stdin for multi-line)")
    group.add_argument("--code-file", help="read code from this file, or '-' for stdin")
    group.add_argument("--stdin", action="store_true", help="read code from stdin")
    parser.add_argument("--timeout", type=float, default=60.0,
                        help="seconds to wait for execution to finish (default 60)")
    parser.add_argument("--connect-timeout", type=float, default=30.0,
                        help="seconds to wait for the kernel to become responsive (default 30)")
    parser.add_argument("--http-timeout", type=float, default=30.0,
                        help="seconds for each REST call (default 30)")
    parser.add_argument("--url", default=os.environ.get("JUPYTER_TUTOR_URL", DEFAULT_URL),
                        help="Jupyter server base URL (default %s, or $JUPYTER_TUTOR_URL)" % DEFAULT_URL)
    parser.add_argument("--kernel", default="python3", help="kernelspec name (default python3)")
    parser.add_argument("--max-chars", type=int, default=20000,
                        help="clip each text field to this many characters; 0 = unlimited")
    parser.add_argument("--silent", action="store_true",
                        help="suppress output and history (kernel-side silent=True)")
    parser.add_argument("--no-store-history", action="store_true",
                        help="do not advance the execution counter")
    parser.add_argument("--no-interrupt-on-timeout", action="store_true",
                        help="on timeout, leave the kernel running the cell")
    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    started = time.monotonic()
    base_url = args.url
    kernel_id = None
    token = None

    try:
        token = resolve_token()
        code = _read_code(args)
        session = ensure_session(base_url, token, args.path, args.kernel, args.http_timeout)
        kernel_id = session["kernel"]["id"]
        ws_session_id = uuid.uuid4().hex  # fresh: a repeat evicts the other client
        ws = _connect(_ws_url(base_url, kernel_id, ws_session_id), token, args.connect_timeout)
    except UsageError as exc:
        _emit({"ok": False, "status": "usage_error", "message": str(exc)})
        return EXIT_USAGE
    except TransportError as exc:
        _emit({"ok": False, "status": "transport_error", "message": str(exc),
               "kernel_id": kernel_id})
        return EXIT_TRANSPORT

    collector = Collector(args.max_chars)
    try:
        try:
            await_channels(ws, ws_session_id, time.monotonic() + args.connect_timeout)
            status, msg_id = execute(
                ws,
                ws_session_id,
                code,
                time.monotonic() + args.timeout,
                collector,
                args.silent,
                not args.no_store_history,
            )
        finally:
            try:
                ws.close()
            except Exception:  # noqa: BLE001
                pass
    except TransportError as exc:
        _emit({"ok": False, "status": "transport_error", "message": str(exc),
               "kernel_id": kernel_id})
        return EXIT_TRANSPORT

    interrupted = None
    if status == "timeout" and not args.no_interrupt_on_timeout:
        interrupted = interrupt_kernel(base_url, token, kernel_id, args.http_timeout)

    stdout, stderr = collector.finish()
    payload = {
        "ok": status == "ok",
        "status": status,
        "path": args.path,
        "kernel_id": kernel_id,
        "kernel_name": (session.get("kernel") or {}).get("name"),
        "session_id": session.get("id"),
        "msg_id": msg_id,
        "execution_count": collector.execution_count,
        "elapsed_s": round(time.monotonic() - started, 3),
        "stdout": stdout,
        "stderr": stderr,
        "results": collector.results,
        "display": collector.display,
        "error": collector.error,
        "truncated": collector.truncated,
    }
    if collector.dropped_buffers:
        payload["dropped_binary_buffers"] = collector.dropped_buffers
    if collector.stdin_blocked:
        payload["stdin_blocked"] = True
    if interrupted is not None:
        payload["interrupt_requested"] = interrupted
    _emit(payload)

    if status == "timeout":
        return EXIT_TIMEOUT
    if status != "ok":
        return EXIT_KERNEL_ERROR
    return EXIT_OK


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
