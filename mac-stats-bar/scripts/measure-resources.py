#!/usr/bin/env python3
"""Read-only RSS / CPU sampling of this app and its own descendants."""
import argparse
import datetime
import json
from pathlib import Path
import subprocess
import time


def cpu_seconds(value):
    total = 0.0
    for part in value.split(":"):
        total = total * 60 + float(part)
    return total


def read_processes():
    output = subprocess.check_output(["ps", "-axo", "pid=,ppid=,rss=,time=,comm="], text=True)
    result = []
    for line in output.splitlines():
        fields = line.strip().split(None, 4)
        if len(fields) != 5:
            continue
        try:
            result.append({"pid": int(fields[0]), "parent": int(fields[1]), "rssKiB": int(fields[2]),
                           "cpuSeconds": cpu_seconds(fields[3]), "path": fields[4]})
        except ValueError:
            pass
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pid", type=int)
    parser.add_argument("--diagnostic", action="store_true")
    parser.add_argument("--flavor", choices=("preview", "stable"), default="preview",
                        help="Bundle to measure; defaults to the same preview bundle as build.sh")
    parser.add_argument("--seconds", type=float, default=30)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    if args.diagnostic == (args.pid is not None):
        parser.error("Choose --pid or --diagnostic")
    if not 0 < args.seconds < float("inf"):
        parser.error("--seconds must be a finite positive number")
    root = Path(__file__).resolve().parent.parent
    app_name = "Mac Stats Bar Preview.app" if args.flavor == "preview" else "Mac Stats Bar.app"
    executable = root / "dist" / app_name / "Contents/MacOS/MacStatsBar"
    process = None
    if args.diagnostic:
        process = subprocess.Popen([str(executable), "--diagnose"], stdout=subprocess.PIPE,
                                   stderr=subprocess.DEVNULL, text=True)
        pid = process.pid
    else:
        pid = args.pid
    interval = 0.1 if process else 2.5
    samples = []
    start = time.monotonic()
    try:
        while time.monotonic() - start <= args.seconds:
            rows = read_processes()
            if process and process.poll() is not None:
                break
            matches = [r for r in rows if r["pid"] == pid]
            if not matches:
                if process and process.poll() is not None:
                    break
                raise RuntimeError("The selected process is no longer running")
            app = matches[0]
            # Popen identifies our own child even during exec/exit name changes.
            if process is None and Path(app["path"]).resolve() != executable:
                raise RuntimeError("Selected PID is not this workspace's Mac Stats Bar")
            descendants = {pid}
            while True:
                more = {r["pid"] for r in rows if r["parent"] in descendants}
                if more <= descendants:
                    break
                descendants |= more
            children = [r for r in rows if r["pid"] in descendants and r["pid"] != pid]
            samples.append({"elapsedSeconds": round(time.monotonic() - start, 3),
                            "appRssMiB": round(app["rssKiB"] / 1024, 3), "appCPUSeconds": app["cpuSeconds"],
                            "childCount": len(children),
                            "childRssMiB": round(sum(r["rssKiB"] for r in children) / 1024, 3)})
            time.sleep(interval)
        if not samples:
            raise RuntimeError("No samples collected")
        elapsed = samples[-1]["elapsedSeconds"] - samples[0]["elapsedSeconds"]
        cpu = samples[-1]["appCPUSeconds"] - samples[0]["appCPUSeconds"]
        report = {
            "appBundle": app_name,
            "measuredAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "scenario": "one-shot native diagnostic + Codex usage read" if process else "panel closed; system every 5 s; quota every 300 s",
            "durationSeconds": round(elapsed, 3),
            "averageAppCPUPercentOfOneCore": round(cpu / elapsed * 100, 3) if elapsed else None,
            "appRssMinMiB": min(s["appRssMiB"] for s in samples),
            "appRssMaxMiB": max(s["appRssMiB"] for s in samples),
            "maximumChildCount": max(s["childCount"] for s in samples),
            "observedChildPeakRssMiB": max(s["childRssMiB"] for s in samples),
            "samples": samples,
        }
        if process:
            output, _ = process.communicate(timeout=5)
            if process.returncode != 0:
                raise RuntimeError("Diagnostic failed: " + output)
            report["diagnostic"] = json.loads(output)
        destination = Path(args.output)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        print(json.dumps({k: v for k, v in report.items() if k not in ("samples", "diagnostic")}, indent=2))
    finally:
        if process and process.poll() is None:
            process.terminate()
            process.wait(timeout=3)


if __name__ == "__main__":
    main()
