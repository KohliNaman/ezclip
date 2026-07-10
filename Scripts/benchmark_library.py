#!/usr/bin/env python3
import argparse
import json
import os
import sqlite3
import statistics
import tempfile
import time


def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int((len(ordered) - 1) * fraction))]


def timed(connection, sql, arguments=(), iterations=30):
    samples = []
    for _ in range(3):
        connection.execute(sql, arguments).fetchall()
    for _ in range(iterations):
        started = time.perf_counter_ns()
        connection.execute(sql, arguments).fetchall()
        samples.append((time.perf_counter_ns() - started) / 1_000_000)
    return {"p50_ms": round(statistics.median(samples), 3), "p95_ms": round(percentile(samples, 0.95), 3)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=50_000)
    parser.add_argument("--output")
    args = parser.parse_args()
    handle, path = tempfile.mkstemp(prefix="ezclip-benchmark-", suffix=".sqlite")
    os.close(handle)
    try:
        db = sqlite3.connect(path)
        db.executescript("""
            PRAGMA journal_mode=WAL;
            CREATE TABLE capture(id TEXT PRIMARY KEY, timestamp REAL, appName TEXT, contextType TEXT, kind TEXT);
            CREATE INDEX capture_timestamp ON capture(timestamp DESC, id DESC);
            CREATE INDEX capture_kind ON capture(kind, timestamp DESC);
            CREATE VIRTUAL TABLE captureSearchFTS USING fts5(captureId UNINDEXED, content, tokenize='unicode61 remove_diacritics 2');
        """)
        kinds = ["music", "conversation", "booking", "place", "article", "design", "product", "social", "document", "other"]
        rows = []
        search_rows = []
        for index in range(args.count):
            capture_id = f"capture-{index:06d}"
            kind = kinds[index % len(kinds)]
            rows.append((capture_id, float(args.count - index), f"App {index % 17}", "website", kind))
            search_rows.append((capture_id, f"{kind} kyoto hotel song article design product person topic-{index % 997}"))
        db.executemany("INSERT INTO capture VALUES (?, ?, ?, ?, ?)", rows)
        db.executemany("INSERT INTO captureSearchFTS VALUES (?, ?)", search_rows)
        db.commit()

        results = {
            "capture_count": args.count,
            "first_page": timed(db, "SELECT * FROM capture ORDER BY timestamp DESC, id DESC LIMIT 200"),
            "kind_filter": timed(db, "SELECT * FROM capture WHERE kind = ? ORDER BY timestamp DESC LIMIT 200", ("booking",)),
            "fts_search": timed(db, "SELECT capture.* FROM capture JOIN captureSearchFTS ON captureSearchFTS.captureId = capture.id WHERE captureSearchFTS MATCH ? ORDER BY capture.timestamp DESC LIMIT 200", ('"kyoto"* AND "hotel"*',)),
        }
        results["budgets_ms"] = {"first_page_p95": 100, "kind_filter_p95": 100, "fts_search_p95": 120}
        output = json.dumps(results, indent=2, sort_keys=True)
        print(output)
        if args.output:
            with open(args.output, "w", encoding="utf-8") as file:
                file.write(output + "\n")
        failed = results["first_page"]["p95_ms"] >= 100 or results["kind_filter"]["p95_ms"] >= 100 or results["fts_search"]["p95_ms"] >= 120
        raise SystemExit(1 if failed else 0)
    finally:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    main()
