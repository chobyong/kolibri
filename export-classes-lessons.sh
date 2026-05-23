#!/usr/bin/env bash
# Exports Kolibri classes and lessons to classes-lessons.json.
# Copy that file to a new host, then run:
#   sudo ./import-classes-lessons.sh classes-lessons.json

set -euo pipefail

KOLIBRI_URL="${1:-http://localhost:8080}"
OUTPUT="${2:-/opt/him-edu/classes-lessons.json}"
USERNAME="${KOLIBRI_USERNAME:-him}"
PASSWORD="${KOLIBRI_PASSWORD:-ABCD_1234}"

echo "Exporting classes and lessons from $KOLIBRI_URL ..."

python3 - <<PYEOF
import json, sys, urllib.request, urllib.error, http.cookiejar

BASE = "$KOLIBRI_URL"
OUTPUT = "$OUTPUT"

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

# Establish session (gets cookies)
try:
    opener.open(BASE + "/en/user/")
except Exception:
    pass

try:
    session = post("/api/auth/session/", {"username": "$USERNAME", "password": "$PASSWORD"})
except urllib.error.HTTPError as e:
    print(f"ERROR: Login failed ({e.code}). Check credentials.", file=sys.stderr)
    sys.exit(1)

facility_id = session.get("facility_id") or ""
print(f"Logged in as: {session.get('username')}  facility: {facility_id}")

# Fetch classrooms
classrooms_raw = get("/api/auth/classroom/?limit=200")
if isinstance(classrooms_raw, dict):
    classrooms_raw = classrooms_raw.get("results", classrooms_raw)

# Fetch all lessons
lessons_raw = get("/api/lessons/lesson/?limit=500")
if isinstance(lessons_raw, dict):
    lessons_raw = lessons_raw.get("results", lessons_raw)

# Build classroom-keyed output
classroom_map = {}
for c in classrooms_raw:
    classroom_map[c["id"]] = {
        "name": c["name"],
        "lessons": []
    }

for lesson in lessons_raw:
    cid = lesson.get("collection")
    entry = {
        "title": lesson["title"],
        "description": lesson.get("description", ""),
        "active": lesson.get("active", True),
        "resources": lesson.get("resources", []),
    }
    if cid in classroom_map:
        classroom_map[cid]["lessons"].append(entry)
    else:
        # Lesson belongs to a classroom not in our list — include it under "_unknown"
        classroom_map.setdefault("_unknown", {"name": "_unknown", "lessons": []})["lessons"].append(entry)

output = {
    "kolibri_url": BASE,
    "facility_id": facility_id,
    "classrooms": list(classroom_map.values()),
}

with open(OUTPUT, "w") as f:
    json.dump(output, f, indent=2)

total_lessons = sum(len(c["lessons"]) for c in output["classrooms"])
print(f"Saved {len(output['classrooms'])} class(es), {total_lessons} lesson(s) to {OUTPUT}")
for c in output["classrooms"]:
    print(f"  Class '{c['name']}': {len(c['lessons'])} lesson(s)")
    for l in c["lessons"]:
        print(f"    - {l['title']}  ({len(l['resources'])} resource(s))")
PYEOF
