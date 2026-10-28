"""Measure actual SQL generation speed and save the returned database timings."""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
from statistics import median
import platform
import db


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=10000)
    parser.add_argument("--batch-size", type=int, default=100)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--locale", choices=["all", "zh-CN", "ko-KR"], default="all")
    parser.add_argument(
        "--environment", default="PostgreSQL connected through DATABASE_URL"
    )
    parser.add_argument("--output", default="benchmark_results.json")
    args = parser.parse_args()
    if not 1 <= args.runs <= 10:
        parser.error("--runs must be 1..10")
    results = []
    for locale in (["zh-CN", "ko-KR"] if args.locale == "all" else [args.locale]):
        runs = []
        for number in range(args.runs):
            item = db.benchmark(locale, 42, args.count, args.batch_size)
            runs.append(item)
            print(
                f"{locale}, run {number+1}: {item['users']} users / {item['seconds']:.3f} s = {item['users_per_second']:,.2f} users/s",
                flush=True,
            )
        results.append(
            {
                "locale": locale,
                "median_users_per_second": median(x["users_per_second"] for x in runs),
                "runs": runs,
            }
        )
    output = {
        "measured_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "environment": args.environment,
        "client_platform": platform.platform(),
        "seed": 42,
        "requested_count": args.count,
        "batch_size": args.batch_size,
        "results": results,
    }
    Path(args.output).write_text(
        json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print("Saved", args.output)


if __name__ == "__main__":
    main()
