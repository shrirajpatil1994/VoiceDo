#!/bin/bash
# VoiceDo Module Bug-Debug Check
# Usage: ./scripts/debug_check.sh --module <N>
# Output: BugReports/module-<N>-bugs.md
# Exit: 0 = CLEAN, 1 = BUGS_FOUND

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REPORTS_DIR="$PROJECT_DIR/BugReports"
DATE=$(date +"%Y-%m-%d %H:%M:%S")

# --- Parse args ---
MODULE=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --module) MODULE="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 2 ;;
  esac
done

if [[ -z "$MODULE" ]]; then
  echo "Error: --module <N> is required"
  exit 2
fi

REPORT_FILE="$REPORTS_DIR/module-${MODULE}-bugs.md"
mkdir -p "$REPORTS_DIR"

echo "Running bug-debug check for Module $MODULE..."
echo "Report will be written to: $REPORT_FILE"

# --- Detect best available iOS simulator ---
detect_simulator() {
  # Query simctl for booted or available iPhones, prefer iPhone 16/15
  local udid
  udid=$(xcrun simctl list devices available -j 2>/dev/null \
    | python3 -c "
import json,sys
data=json.load(sys.stdin)
candidates=[]
for runtime,devices in data['devices'].items():
    if 'iOS' not in runtime and 'ios' not in runtime.lower():
        continue
    for d in devices:
        if d.get('isAvailable') and 'iPhone' in d['name']:
            candidates.append((runtime, d['name'], d['udid']))
# Prefer iPhone 16, then 15, then any iPhone
for preferred in ['iPhone 16','iPhone 15','iPhone']:
    for r,n,u in candidates:
        if preferred in n:
            print(u)
            sys.exit(0)
" 2>/dev/null || true)
  echo "$udid"
}

SIMULATOR_UDID=$(detect_simulator)

if [[ -z "$SIMULATOR_UDID" ]]; then
  DESTINATION_AVAILABLE=false
  DESTINATION_STR="(no simulator available)"
  echo "⚠️  No iOS simulator found. To download one:"
  echo "    Open Xcode → Settings → Components → iOS → click download next to iOS 26"
  echo "    Or run: xcodebuild -downloadPlatform iOS"
else
  DESTINATION_AVAILABLE=true
  DESTINATION_STR="platform=iOS Simulator,id=${SIMULATOR_UDID}"
  echo "✓  Using simulator: $SIMULATOR_UDID"
fi

# --- Collect results ---
TEST_FAILURES=""
TEST_STATUS="SKIPPED"
LINT_VIOLATIONS=""
ANALYSIS_WARNINGS=""
TODO_LIST=""
HAS_BUGS=false

# 1. Build + Test
echo ""
echo "[1/4] Running tests..."

if [[ "$DESTINATION_AVAILABLE" == "true" ]]; then
  BUILD_LOG=$(mktemp)
  set +e
  xcodebuild test \
    -scheme VoiceDo \
    -destination "$DESTINATION_STR" \
    -quiet \
    -allowProvisioningUpdates \
    2>&1 | tee "$BUILD_LOG" | grep -E "error:|FAILED|Test Suite" | head -50
  BUILD_EXIT=${PIPESTATUS[0]}
  set -e

  if [[ $BUILD_EXIT -eq 0 ]]; then
    TEST_STATUS="PASSED"
  else
    TEST_STATUS="FAILED"
    HAS_BUGS=true
    TEST_FAILURES=$(grep -E "error:|FAILED|XCTAssert" "$BUILD_LOG" 2>/dev/null \
      | grep -v "^$" \
      | head -30 \
      | sed 's|'"$PROJECT_DIR"'/||g' \
      || echo "See raw build log for details")
  fi
  rm -f "$BUILD_LOG"
else
  TEST_STATUS="SKIPPED — no simulator installed"
  echo "  Skipping tests (no simulator). Download iOS runtime to enable."
  echo "  Run: xcodebuild -downloadPlatform iOS"
fi

# 2. SwiftLint
echo ""
echo "[2/4] Running SwiftLint..."
if command -v swiftlint &>/dev/null; then
  set +e
  LINT_OUT=$(cd "$PROJECT_DIR" && swiftlint lint --reporter github-actions-logging 2>&1)
  LINT_EXIT=$?
  set -e
  if [[ $LINT_EXIT -ne 0 ]] || echo "$LINT_OUT" | grep -q " error:"; then
    HAS_BUGS=true
  fi
  LINT_VIOLATIONS=$(echo "$LINT_OUT" | head -50 | sed 's|'"$PROJECT_DIR"'/||g')
  if [[ -z "$LINT_VIOLATIONS" ]]; then
    LINT_VIOLATIONS="None"
  fi
else
  LINT_VIOLATIONS="SwiftLint not installed. Run: brew install swiftlint"
  # Not a blocking bug — just informational
  echo "  SwiftLint not installed (brew install swiftlint)"
fi

# 3. Static Analysis
echo ""
echo "[3/4] Running static analysis..."

if [[ "$DESTINATION_AVAILABLE" == "true" ]]; then
  ANALYZE_LOG=$(mktemp)
  set +e
  xcodebuild analyze \
    -scheme VoiceDo \
    -destination "$DESTINATION_STR" \
    -quiet \
    -allowProvisioningUpdates \
    2>&1 | tee "$ANALYZE_LOG" | grep -E "warning:|error:" | head -30
  set -e

  ANALYSIS_WARNINGS=$(grep -E "warning:|error:" "$ANALYZE_LOG" 2>/dev/null \
    | grep -v "^$" \
    | head -30 \
    | sed 's|'"$PROJECT_DIR"'/||g' \
    || echo "None")
  [[ -z "$ANALYSIS_WARNINGS" ]] && ANALYSIS_WARNINGS="None"
  rm -f "$ANALYZE_LOG"
else
  ANALYSIS_WARNINGS="Skipped — no simulator installed"
fi

# 4. TODO/FIXME scan — source files only, exclude all build artefacts
echo ""
echo "[4/4] Scanning for TODOs and FIXMEs in source files..."

TODO_LIST=$(grep -rn "TODO:\|FIXME:\|HACK:\|XXX:" \
  "$PROJECT_DIR/VoiceDo" \
  "$PROJECT_DIR/VoiceDoWidget" \
  "$PROJECT_DIR/VoiceDoTests" \
  "$PROJECT_DIR/Packages/VoiceDoShared/Sources" \
  "$PROJECT_DIR/Packages/VoiceDoShared/Tests" \
  2>/dev/null \
  | grep -v "\.swiftlint\.yml" \
  | grep -v "\.build/" \
  | grep -v "/DerivedData/" \
  | sed 's|'"$PROJECT_DIR"'/||g' \
  | head -50 \
  || true)

if [[ -z "$TODO_LIST" ]]; then
  TODO_LIST="None"
fi

if [[ "$TODO_LIST" != "None" ]]; then
  HAS_BUGS=true
fi

# --- Determine overall status ---
if $HAS_BUGS; then
  STATUS="BUGS_FOUND"
else
  STATUS="CLEAN"
fi

# --- Write report ---
cat > "$REPORT_FILE" << REPORT_EOF
# Module ${MODULE} Bug Report — ${DATE}
## Status: ${STATUS}

## Test Results: ${TEST_STATUS}
\`\`\`
${TEST_FAILURES:-None}
\`\`\`

## SwiftLint Violations
\`\`\`
${LINT_VIOLATIONS}
\`\`\`

## Static Analysis Warnings
\`\`\`
${ANALYSIS_WARNINGS}
\`\`\`

## Unresolved TODOs / FIXMEs (source files only)
\`\`\`
${TODO_LIST}
\`\`\`

## Summary for Claude
<!-- Paste this entire section into Claude to request fixes -->

Module ${MODULE} bug-debug check completed on ${DATE} with status: **${STATUS}**.

$(if $HAS_BUGS; then
echo "Issues found that must be fixed before this module can be locked:"
[[ "$TEST_STATUS" == FAILED* ]] && echo "- Test failures: $(echo "$TEST_FAILURES" | head -3)"
echo "$LINT_VIOLATIONS" | grep -q " error:" 2>/dev/null && echo "- SwiftLint errors present (see above)"
[[ "$TODO_LIST" != "None" ]] && echo "- Unresolved TODO/FIXME markers in source files (see above)"
echo ""
echo "Please fix all issues listed above in the VoiceDo Xcode project, then re-run:"
echo "\`\`\`"
echo "./scripts/debug_check.sh --module ${MODULE}"
echo "\`\`\`"
else
echo "All checks passed. Module ${MODULE} is ready to be locked."
fi)

---
### Environment notes
- Xcode: $(xcodebuild -version 2>/dev/null | head -1 || echo "not found")
- Simulator: ${DESTINATION_STR}
- SwiftLint: $(swiftlint version 2>/dev/null || echo "not installed")
REPORT_EOF

echo ""
echo "=============================="
echo "Module $MODULE check: $STATUS"
echo "Report: $REPORT_FILE"
echo "=============================="

if $HAS_BUGS; then
  exit 1
else
  exit 0
fi
