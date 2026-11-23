import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "exporter"))
import exporter  # noqa: E402


def test_collect_has_expected_keys():
    m = exporter.collect()
    for key in ("cpu_percent", "memory_percent", "uptime_seconds", "disks", "load1"):
        assert key in m
    assert 0 <= m["memory_percent"] <= 100


def test_render_format():
    sample = {
        "cpu_percent": 12.5, "memory_percent": 40, "memory_available_bytes": 1024,
        "load1": 0.5, "load5": 0.4, "load15": 0.3, "uptime_seconds": 3600,
        "disks": [{"mount": "/", "used_percent": 55, "free_bytes": 10, "total_bytes": 20}],
    }
    text = exporter.render(sample, host="test")
    assert '# TYPE server_cpu_usage_percent gauge' in text
    assert 'server_cpu_usage_percent{host="test"} 12.5000' in text
    assert 'server_disk_usage_percent{host="test",mount="/"} 55.0000' in text
    assert 'server_load_average{host="test",period="5m"} 0.4000' in text
    assert text.endswith("\n")
