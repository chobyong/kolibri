#!/usr/bin/env bash
# Creates demo Kolibri accounts: student1..studentN plus matching classes
# (Class 1..Class N), and enrolls each student in their matching class.
# Idempotent — safe to re-run; skips anything that already exists.
#
# Usage: ./create-demo-classroom.sh [count] [password] [kolibri_url]
#   count        Number of students/classes to create (default: 10)
#   password     Password for all demo students   (default: 1234567890)
#   kolibri_url  Kolibri base URL                  (default: http://localhost:8080)

set -euo pipefail

COUNT="${1:-10}"
STUDENT_PASSWORD="${2:-1234567890}"
KOLIBRI_URL="${3:-http://localhost:8080}"
USERNAME="${KOLIBRI_USERNAME:-him}"
PASSWORD="${KOLIBRI_PASSWORD:-ABCD_1234}"

echo "Waiting for Kolibri to be reachable at $KOLIBRI_URL ..."
tries=0
until curl -fsS -o /dev/null "$KOLIBRI_URL/api/auth/facility/" 2>/dev/null; do
  tries=$((tries + 1))
  if [ "$tries" -ge 60 ]; then
    echo "ERROR: Kolibri not reachable at $KOLIBRI_URL after 120s — skipping demo classroom setup." >&2
    exit 1
  fi
  sleep 2
done

python3 - <<PYEOF
import json, sys, urllib.request, urllib.error, http.cookiejar

BASE = "$KOLIBRI_URL"
USERNAME = "$USERNAME"
PASSWORD = "$PASSWORD"
STUDENT_PASSWORD = "$STUDENT_PASSWORD"
N = $COUNT

cjar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cjar))

def get(path):
    resp = opener.open(BASE + path)
    return json.load(resp)

def post(path, data):
    csrf = next((c.value for c in cjar if "csrf" in c.name.lower()), "")
    body = json.dumps(data).encode()
    req = urllib.request.Request(
        BASE + path, data=body,
        headers={
            "Content-Type": "application/json",
            "X-CSRFToken": csrf,
            "Referer": BASE + "/en/user/",
        }
    )
    resp = opener.open(req)
    return json.load(resp)

def list_all(path):
    raw = get(path)
    if isinstance(raw, dict):
        raw = raw.get("results", raw)
    return raw

try:
    opener.open(BASE + "/en/user/")
except Exception:
    pass

try:
    session = post("/api/auth/session/", {"username": USERNAME, "password": PASSWORD})
except urllib.error.HTTPError as e:
    print(f"ERROR: Login failed ({e.code}): {e.read().decode()}", file=sys.stderr)
    sys.exit(1)

facility_id = session.get("facility_id") or ""
print(f"Logged in as: {session.get('username')}  facility: {facility_id}")

users_by_name = {u["username"]: u["id"] for u in list_all(f"/api/auth/facilityuser/?facility={facility_id}")}
classrooms_by_name = {c["name"]: c["id"] for c in list_all("/api/auth/classroom/?limit=200")}

created_users = skipped_users = 0
print("\n--- Students ---")
for i in range(1, N + 1):
    username = f"student{i}"
    if username in users_by_name:
        print(f"  {username}: already exists — skipping")
        skipped_users += 1
        continue
    try:
        result = post("/api/auth/facilityuser/", {
            "username": username,
            "full_name": f"Student {i}",
            "password": STUDENT_PASSWORD,
            "facility": facility_id,
        })
        users_by_name[username] = result["id"]
        print(f"  {username}: created")
        created_users += 1
    except urllib.error.HTTPError as e:
        print(f"  {username}: ERROR {e.code} {e.read().decode()[:200]}", file=sys.stderr)

created_classes = skipped_classes = 0
print("\n--- Classes ---")
for i in range(1, N + 1):
    cname = f"Class {i}"
    if cname in classrooms_by_name:
        print(f"  {cname}: already exists — skipping")
        skipped_classes += 1
        continue
    try:
        result = post("/api/auth/classroom/", {"name": cname, "parent": facility_id})
        classrooms_by_name[cname] = result["id"]
        print(f"  {cname}: created")
        created_classes += 1
    except urllib.error.HTTPError as e:
        print(f"  {cname}: ERROR {e.code} {e.read().decode()[:200]}", file=sys.stderr)

existing_pairs = {(m["user"], m["collection"]) for m in list_all("/api/auth/membership/?limit=1000")}

created_memberships = skipped_memberships = 0
print("\n--- Enrollments (studentN -> Class N) ---")
for i in range(1, N + 1):
    uname = f"student{i}"
    cname = f"Class {i}"
    uid = users_by_name.get(uname)
    cid = classrooms_by_name.get(cname)
    if not uid or not cid:
        print(f"  {uname} -> {cname}: MISSING user or class, skipping")
        continue
    if (uid, cid) in existing_pairs:
        print(f"  {uname} -> {cname}: already enrolled — skipping")
        skipped_memberships += 1
        continue
    try:
        post("/api/auth/membership/", {"user": uid, "collection": cid})
        print(f"  {uname} -> {cname}: enrolled")
        created_memberships += 1
    except urllib.error.HTTPError as e:
        print(f"  {uname} -> {cname}: ERROR {e.code} {e.read().decode()[:200]}", file=sys.stderr)

print("\n" + "=" * 50)
print(f"Students:    {created_users} created, {skipped_users} skipped")
print(f"Classes:     {created_classes} created, {skipped_classes} skipped")
print(f"Enrollments: {created_memberships} created, {skipped_memberships} skipped")
PYEOF
