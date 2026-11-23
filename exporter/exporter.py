"""Minimal Prometheus exporter for host metrics (CPU, memory, disk, uptime).

Exposes metrics in the Prometheus text format on /metrics using only psutil and
the standard library.
"""
import os
import socket
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import psutil

PREFIX = "server"
HOST = socket.gethostname()


def collect() -> dict:
    vm = psutil.virtual_memory()
    disks = []
    for part in psutil.disk_partitions(all=False):
        try:
            usage = psutil.disk_usage(part.mountpoint)
        except (PermissionError, OSError):
            continue
        disks.append({"mount": part.mountpoint, "used_percent": usage.percent,
                      "free_bytes": usage.free, "total_bytes": usage.total})
    load1, load5, load15 = os.getloadavg()
    return {
        "cpu_percent": psutil.cpu_percent(interval=None),
        "memory_percent": vm.percent,
        "memory_available_bytes": vm.available,
        "load1": load1, "load5": load5, "load15": load15,
        "uptime_seconds": time.time() - psutil.boot_time(),
        "disks": disks,
    }


def render(m: dict, host: str = HOST) -> str:
    """Render collected metrics in the Prometheus exposition format."""
    lines = []

    def gauge(name, help_text, value, labels=None):
        labels = {"host": host, **(labels or {})}
        label_str = ",".join(f'{k}="{v}"' for k, v in labels.items())
        lines.append(f"{PREFIX}_{name}{{{label_str}}} {float(value):.4f}")

    def header(name, help_text):
        lines.append(f"# HELP {PREFIX}_{name} {help_text}")
        lines.append(f"# TYPE {PREFIX}_{name} gauge")

    header("up", "1 if the exporter is running")
    gauge("up", "", 1)
    header("cpu_usage_percent", "CPU utilisation percent")
    gauge("cpu_usage_percent", "", m["cpu_percent"])
    header("memory_usage_percent", "Memory used percent")
    gauge("memory_usage_percent", "", m["memory_percent"])
    header("memory_available_bytes", "Memory available in bytes")
    gauge("memory_available_bytes", "", m["memory_available_bytes"])
    header("load_average", "System load average")
    for period, key in (("1m", "load1"), ("5m", "load5"), ("15m", "load15")):
        gauge("load_average", "", m[key], {"period": period})
    header("uptime_seconds", "Seconds since boot")
    gauge("uptime_seconds", "", m["uptime_seconds"])
    header("disk_usage_percent", "Disk used percent per mount")
    for d in m["disks"]:
        gauge("disk_usage_percent", "", d["used_percent"], {"mount": d["mount"]})
    header("disk_free_bytes", "Disk free bytes per mount")
    for d in m["disks"]:
        gauge("disk_free_bytes", "", d["free_bytes"], {"mount": d["mount"]})
    return "\n".join(lines) + "\n"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802 - required name
        if self.path == "/metrics":
            body = render(collect()).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
        elif self.path == "/health":
            body = b"ok\n"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
        else:
            body = b"see /metrics\n"
            self.send_response(404)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):  # keep container logs quiet
        pass


def main():
    port = int(os.environ.get("EXPORTER_PORT", "9200"))
    psutil.cpu_percent(interval=None)  # prime the CPU counter
    print(f"exporter listening on :{port}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
