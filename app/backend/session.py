"""OmniLink Mobile Engine - Session Runner and Process Lifecycle Management."""

import enum
import os
import signal
import subprocess
import threading
from dataclasses import dataclass
from typing import Callable, Optional
from gi.repository import GLib


class SessionState(enum.Enum):
    IDLE = "Parado"
    STARTING = "Iniciando..."
    RUNNING = "Em Execução"
    STOPPING = "Finalizando e Restaurando..."
    ERROR = "Erro"


@dataclass
class SessionOptions:
    mode: str = "max"  # max, eco, dex, mirror, virtual, otg
    window_orientation: str = "auto"  # auto, horizontal, vertical
    orientation: str = "auto"  # backwards compatibility alias
    lock_laptop: bool = True
    audio_route: str = "dual"  # dual, pc, off
    screen_off: bool = True
    uhid_gamepad: bool = True
    uhid_keyboard: bool = True
    uhid_mouse: bool = True


class SessionManager:
    """Controls the background omnilink engine process with thread-safe callbacks."""

    def __init__(self, script_path: str):
        self.script_path = os.path.abspath(script_path)
        self.process: Optional[subprocess.Popen] = None
        self.state = SessionState.IDLE
        self._reader_thread: Optional[threading.Thread] = None
        self._lock = threading.Lock()

    def is_running(self) -> bool:
        with self._lock:
            return self.process is not None and self.process.poll() is None

    def start_session(
        self,
        options: SessionOptions,
        on_log: Callable[[str], None],
        on_state_change: Callable[[SessionState], None],
    ):
        """Starts a new scrcpy/omnilink session."""
        with self._lock:
            if self.process is not None and self.process.poll() is None:
                return

            self._set_state(SessionState.STARTING, on_state_change)

            # Build command args
            cmd = [self.script_path, "-y"]

            if options.mode == "max":
                cmd.append("--max")
            elif options.mode == "eco":
                cmd.append("--eco")
            elif options.mode == "dex":
                cmd.append("--dex")
            elif options.mode == "mirror":
                cmd.append("--mirror")
            elif options.mode == "virtual":
                cmd.append("--virtual")
            elif options.mode == "otg":
                cmd.append("--otg")

            if options.window_orientation == "horizontal" or options.orientation == "landscape":
                cmd.append("--window-horizontal")
            elif options.window_orientation == "vertical" or options.orientation == "portrait":
                cmd.append("--window-vertical")
            else:
                cmd.append("--window-auto")

            if options.lock_laptop:
                cmd.append("--lock-laptop")

            if options.audio_route == "dual":
                cmd.append("--audio-dual")
            elif options.audio_route == "pc":
                cmd.append("--audio-pc")
            elif options.audio_route == "off":
                cmd.append("--audio-off")

            if options.screen_off:
                cmd.append("--turn-screen-off")
            else:
                cmd.append("--keep-screen-on")

            # Environment
            env = os.environ.copy()
            env["SNAP_LAUNCHER_NOTICE_ENABLED"] = "false"

            try:
                # Use setsid to run in new process group so SIGINT reaches all children
                self.process = subprocess.Popen(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1,
                    preexec_fn=os.setsid,
                    env=env,
                )
                self._set_state(SessionState.RUNNING, on_state_change)
            except Exception as e:
                self._set_state(SessionState.ERROR, on_state_change)
                GLib.idle_add(on_log, f"[ERRO] Falha ao iniciar processo: {e}\n")
                return

        def reader():
            try:
                for line in iter(self.process.stdout.readline, ""):
                    if not line:
                        break
                    GLib.idle_add(on_log, line)
            except Exception:
                pass
            finally:
                if self.process:
                    self.process.wait()
                with self._lock:
                    self.process = None
                    self._set_state(SessionState.IDLE, on_state_change)
                GLib.idle_add(on_log, "[INFO] Sessão finalizada e estado do sistema restaurado.\n")

        self._reader_thread = threading.Thread(target=reader, daemon=True)
        self._reader_thread.start()

    def stop_session(self, on_state_change: Optional[Callable[[SessionState], None]] = None):
        """Stops the active session gracefully via SIGINT so cleanup trap triggers."""
        with self._lock:
            if self.process is None or self.process.poll() is not None:
                return

            if on_state_change:
                self._set_state(SessionState.STOPPING, on_state_change)

            try:
                # Send SIGINT to the process group
                pgid = os.getpgid(self.process.pid)
                os.killpg(pgid, signal.SIGINT)
            except Exception:
                try:
                    self.process.terminate()
                except Exception:
                    pass

    def run_reset_task(
        self,
        on_log: Callable[[str], None],
        on_complete: Callable[[bool], None],
    ):
        """Runs the emergency hardware reset routine asynchronously."""
        def worker():
            cmd = [self.script_path, "--reset"]
            success = False
            try:
                GLib.idle_add(on_log, "\n[INFO] Executando rotina de restauração dos padrões de fábrica...\n")
                proc = subprocess.Popen(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1,
                )
                for line in iter(proc.stdout.readline, ""):
                    if not line:
                        break
                    GLib.idle_add(on_log, line)
                proc.wait()
                success = proc.returncode == 0
            except Exception as e:
                GLib.idle_add(on_log, f"[ERRO] Falha ao restaurar: {e}\n")
            finally:
                GLib.idle_add(on_complete, success)

        t = threading.Thread(target=worker, daemon=True)
        t.start()

    def run_reset_launcher_task(
        self,
        on_log: Callable[[str], None],
        on_complete: Callable[[bool], None],
    ):
        """Runs the home screen launcher reload routine asynchronously."""
        def worker():
            cmd = [self.script_path, "--reset-launcher"]
            success = False
            try:
                GLib.idle_add(on_log, "\n[INFO] Restaurando layout e posições dos ícones da tela inicial...\n")
                proc = subprocess.Popen(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1,
                )
                for line in iter(proc.stdout.readline, ""):
                    if not line:
                        break
                    GLib.idle_add(on_log, line)
                proc.wait()
                success = proc.returncode == 0
            except Exception as e:
                GLib.idle_add(on_log, f"[ERRO] Falha ao recarregar launcher: {e}\n")
            finally:
                GLib.idle_add(on_complete, success)

        t = threading.Thread(target=worker, daemon=True)
        t.start()

    def _set_state(self, state: SessionState, cb: Optional[Callable[[SessionState], None]]):
        self.state = state
        if cb:
            GLib.idle_add(cb, state)
