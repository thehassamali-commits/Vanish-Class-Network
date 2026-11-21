"""
Smoke tests for the Field Sync Server.

Usage:
  1. Start the server (from the server/ folder):
       uvicorn main:app --host 0.0.0.0 --port 8000
  2. Run the tests in another terminal:
       python test_server.py http://localhost:8000
"""
import sys
import uuid

import requests

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000"


def check(name, condition):
    print(("PASS " if condition else "FAIL ") + name)
    return condition


def main():
    ok = True
    ok &= check(
        "health endpoint",
        requests.get(f"{BASE}/health").json() == {"status": "ok"},
    )

    rid = f"test-{uuid.uuid4().hex[:8]}"

    # Create a new record offline (base_version = 0)
    r = requests.post(f"{BASE}/sync/push", json={
        "device_id": "device-A",
        "changes": [{"id": rid, "base_version": 0, "data": {"note": "first"}}],
    }).json()
    ok &= check(
        "create accepted at version 1",
        r["accepted"] == [{"id": rid, "version": 1}] and r["conflicts"] == [],
    )

    # Stale write: base_version 0 again, but server is at version 1
    r = requests.post(f"{BASE}/sync/push", json={
        "device_id": "device-B",
        "changes": [{"id": rid, "base_version": 0, "data": {"note": "stale"}}],
    }).json()
    ok &= check("stale write reported as conflict", len(r["conflicts"]) == 1)

    # Pull from the beginning should include the record
    r = requests.get(f"{BASE}/sync/pull", params={"since": 0}).json()
    ids = [rec["id"] for rec in r["records"]]
    ok &= check("pull returns the created record", rid in ids)

    # Pull with the returned cursor should now be empty
    r2 = requests.get(f"{BASE}/sync/pull", params={"since": r["cursor"]}).json()
    ok &= check("pull after cursor is empty", r2["records"] == [])

    print("\nALL PASSED" if ok else "\nSOME CHECKS FAILED")


if __name__ == "__main__":
    main()
