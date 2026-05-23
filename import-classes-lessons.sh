#!/usr/bin/env bash
# Imports Kolibri classes and lessons from a classes-lessons.json file.
# Generate the file on the source host with:
#   ./export-classes-lessons.sh
# Then copy it here and run:
#   sudo ./import-classes-lessons.sh [classes-lessons.json] [http://localhost:8080]
#
# NOTE: The channels referenced by the lessons must already be installed on this
# host. Run import-kolibri-channels.sh first if needed.

set -euo pipefail

INPUT="${1:-/opt/him-edu/classes-lessons.json}"
KOLIBRI_URL="${2:-http://localhost:8080}"
USERNAME="${KOLIBRI_USERNAME:-him}"
PASSWORD="${KOLIBRI_PASSWORD:-ABCD_1234}"

if [ ! -f "$INPUT" ]; then
  echo "ERROR: File not found: $INPUT"
  echo "Generate it first with:  ./export-classes-lessons.sh"
  exit 1
fi

echo "Importing classes and lessons from $INPUT into $KOLIBRI_URL ..."

python3 - <<PYEOF
import json, sys, urllib.request, urllib.error, http.cookiejar

BASE = "$KOLIBRI_URL"
INPUT = "$INPUT"

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

# Establish session
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

# Load export file
with open(INPUT) as f:
    data = json.load(f)

classrooms_to_import = [c for c in data["classrooms"] if c["name"] != "_unknown"]

# Fetch existing classrooms on this host so we don't duplicate
existing_raw = get("/api/auth/classroom/?limit=200")
if isinstance(existing_raw, dict):
    existing_raw = existing_raw.get("results", existing_raw)
existing_by_name = {c["name"]: c["id"] for c in existing_raw}

created_classes = 0
created_lessons = 0
skipped_lessons = 0

for classroom in classrooms_to_import:
    cname = classroom["name"]

    # Create the class if it doesn't already exist
    if cname in existing_by_name:
        cid = existing_by_name[cname]
        print(f"\nClass '{cname}' already exists — using existing (id: {cid[:8]}...)")
    else:
        try:
            result = post("/api/auth/classroom/", {"name": cname, "parent": facility_id})
            cid = result["id"]
            created_classes += 1
            print(f"\nCreated class '{cname}' (id: {cid[:8]}...)")
        except urllib.error.HTTPError as e:
            body = e.read().decode()
            print(f"\nERROR creating class '{cname}': {e.code} {body[:200]}", file=sys.stderr)
            continue

    # Fetch existing lessons in this class to avoid duplicates
    existing_lessons_raw = get(f"/api/lessons/lesson/?limit=500")
    if isinstance(existing_lessons_raw, dict):
        existing_lessons_raw = existing_lessons_raw.get("results", existing_lessons_raw)
    existing_lesson_titles = {
        l["title"] for l in existing_lessons_raw
        if l.get("collection") == cid or (l.get("classroom") or {}).get("id") == cid
    }

    for lesson in classroom["lessons"]:
        ltitle = lesson["title"]
        if ltitle in existing_lesson_titles:
            print(f"  Lesson '{ltitle}' already exists — skipping")
            skipped_lessons += 1
            continue

        try:
            result = post("/api/lessons/lesson/", {
                "title": ltitle,
                "description": lesson.get("description", ""),
                "resources": lesson.get("resources", []),
                "collection": cid,
                "active": lesson.get("active", True),
                "assignments": [{"collection": cid}],
            })
            created_lessons += 1
            print(f"  Created lesson '{ltitle}' ({len(lesson['resources'])} resource(s))")
        except urllib.error.HTTPError as e:
            body = e.read().decode()
            print(f"  ERROR creating lesson '{ltitle}': {e.code} {body[:200]}", file=sys.stderr)

print()
print("=" * 50)
print(f"Done. Created {created_classes} class(es), {created_lessons} lesson(s).")
if skipped_lessons:
    print(f"Skipped {skipped_lessons} lesson(s) that already exist.")
print(f"Kolibri is at: {BASE}")
PYEOF
