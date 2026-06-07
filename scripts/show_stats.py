#!/usr/bin/env python3
"""Show miner statistics from Qdrant payload data."""
import json, sys, subprocess

def main():
    resp = subprocess.run(
        [
            "curl", "-s", "-X", "POST",
            "http://localhost:6333/collections/compiled_ai_specs/points/scroll",
            "-H", "Content-Type: application/json",
            "-d", json.dumps({"limit": 100}),
        ],
        capture_output=True, text=True,
    )
    try:
        data = json.loads(resp.stdout)
    except json.JSONDecodeError:
        print("  Qdrant not responding. Is 'make up' running?")
        sys.exit(1)

    points = data.get("result", {}).get("points", [])
    if not points:
        print("  No points in collection yet.")
        return

    total = len(points)
    scores = [p["payload"].get("ctx_audit_score") for p in points if p["payload"].get("ctx_audit_score") is not None]
    categories = {}
    for p in points:
        cat = p["payload"].get("category", "unknown")
        categories[cat] = categories.get(cat, 0) + 1

    print(f"  Total specs mined:     {total}")
    if scores:
        print(f"  Avg ctx audit score:   {sum(scores)/len(scores):.1f}")
        print(f"  Max audit score:       {max(scores):.1f}")
        print(f"  Min audit score:       {min(scores):.1f}")
    else:
        print("  Avg ctx audit score:   N/A")
    print("  Categories:")
    for cat, count in sorted(categories.items(), key=lambda x: -x[1]):
        print(f"    {cat:<20} {count}")

if __name__ == "__main__":
    main()
