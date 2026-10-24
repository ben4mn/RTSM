"""Real subprocess coverage for scoped timeout cleanup; no Godot required."""

import ctypes
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

from run_focused_tests import run_case


def process_is_running(pid: int) -> bool:
    if os.name == "nt":
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.OpenProcess.argtypes = [ctypes.c_ulong, ctypes.c_int, ctypes.c_ulong]
        kernel.OpenProcess.restype = ctypes.c_void_p
        kernel.GetExitCodeProcess.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ulong)]
        kernel.CloseHandle.argtypes = [ctypes.c_void_p]
        handle = kernel.OpenProcess(0x1000, 0, pid)
        if not handle:
            return False
        code = ctypes.c_ulong()
        try:
            if not kernel.GetExitCodeProcess(handle, ctypes.byref(code)):
                raise ctypes.WinError(ctypes.get_last_error())
            return code.value == 259  # STILL_ACTIVE
        finally:
            kernel.CloseHandle(handle)
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    stat = Path("/proc") / str(pid) / "stat"
    return not stat.is_file() or stat.read_text().split(") ", 1)[1][0] != "Z"


class FocusedRunnerTests(unittest.TestCase):
    def test_case_retains_output_and_exit_status(self):
        with tempfile.TemporaryDirectory() as folder:
            result = run_case([sys.executable, "-c", "import sys; print('out'); print('err',file=sys.stderr); sys.exit(7)"], cwd=Path(folder), env=os.environ.copy(), timeout=10)
        self.assertEqual(result.returncode, 7)
        self.assertEqual(result.stdout.strip(), "out")
        self.assertEqual(result.stderr.strip(), "err")

    def test_timeout_removes_owned_descendant_and_preserves_unrelated_process(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            child_pid_path = root / "owned-child.pid"
            fixture = root / "spawn_child.py"
            fixture.write_text(
                "import subprocess,sys,time\nfrom pathlib import Path\n"
                "child=subprocess.Popen([sys.executable,'-c','import time; time.sleep(120)'])\n"
                "Path(sys.argv[1]).write_text(str(child.pid))\n"
                "print('owned child ready',flush=True)\ntime.sleep(120)\n",
                encoding="utf-8", newline="\n",
            )
            sentinel = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(120)"])
            child_pid = None
            try:
                started = time.monotonic()
                with self.assertRaises(subprocess.TimeoutExpired) as raised:
                    run_case([sys.executable, str(fixture), str(child_pid_path)], cwd=root, env=os.environ.copy(), timeout=2.0)
                self.assertLess(time.monotonic() - started, 12.0)
                self.assertIn("owned child ready", raised.exception.output)
                child_pid = int(child_pid_path.read_text())
                self.assertFalse(process_is_running(child_pid), "timed-out wrapper left its child alive")
                self.assertIsNone(sentinel.poll(), "cleanup affected an unrelated process")
            finally:
                sentinel.kill()
                sentinel.wait(timeout=10)
                # A failing regression must also clean up its own recorded child.
                if child_pid is None and child_pid_path.exists():
                    child_pid = int(child_pid_path.read_text())
                if child_pid is not None and process_is_running(child_pid):
                    if os.name == "nt":
                        subprocess.run(["taskkill", "/PID", str(child_pid), "/T", "/F"], capture_output=True, timeout=15, check=False)
                    else:
                        os.kill(child_pid, signal.SIGKILL)


if __name__ == "__main__":
    unittest.main()
