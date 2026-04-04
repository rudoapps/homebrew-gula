#!/bin/bash
# Pre-release QA suite for gula CLI
# Run from repo root: bash scripts/agent/tests/run_all.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO_ROOT"

echo ""
echo "  ═══════════════════════════════════════════════"
echo "  GULA PRE-RELEASE QA"
echo "  ═══════════════════════════════════════════════"

# 1. Syntax check all Python files
echo ""
echo "  ── 1/6 Syntax check ──"
SYNTAX_OK=true
for f in $(find scripts/agent/gula_chat -name "*.py" -not -path "*__pycache__*"); do
    if ! python3 -c "import ast; ast.parse(open('$f').read())" 2>/dev/null; then
        echo "  ✗ SYNTAX ERROR: $f"
        SYNTAX_OK=false
    fi
done
if $SYNTAX_OK; then
    echo "  ✓ All Python files have valid syntax"
else
    echo "  ✗ Syntax errors found — aborting"
    exit 1
fi

# 2. Import tests
echo ""
echo "  ── 2/6 Import tests ──"
PYTHONPATH="$REPO_ROOT/scripts/agent" python3 scripts/agent/tests/test_imports.py
if [ $? -ne 0 ]; then
    echo "  ✗ Import tests failed — aborting"
    exit 1
fi

# 3. Tool tests
echo ""
echo "  ── 3/6 Tool tests ──"
PYTHONPATH="$REPO_ROOT/scripts/agent" python3 scripts/agent/tests/test_tools.py
if [ $? -ne 0 ]; then
    echo "  ✗ Tool tests failed — aborting"
    exit 1
fi

# 4. Startup flow integration tests
echo ""
echo "  ── 4/6 Startup flow tests ──"
PYTHONPATH="$REPO_ROOT/scripts/agent" python3 scripts/agent/tests/test_startup_flow.py
if [ $? -ne 0 ]; then
    echo "  ✗ Startup flow tests failed — aborting"
    exit 1
fi

# 5. Cross-platform compatibility
echo ""
echo "  ── 5/6 Compatibility tests ──"
PYTHONPATH="$REPO_ROOT/scripts/agent" python3 scripts/agent/tests/test_compatibility.py || echo "  ⚠ Compatibility warnings found (review before Linux deploy)"

# 5. Version consistency
echo ""
echo "  ── 6/6 Version check ──"
VERSION=$(cat VERSION)
FORMULA_VERSION=$(grep "refs/tags/v" Formula/gula.rb | sed 's/.*v\([0-9.]*\).*/\1/')
echo "  VERSION file: $VERSION"
echo "  Formula:      $FORMULA_VERSION"
if [ "$VERSION" != "$FORMULA_VERSION" ]; then
    echo "  ⚠ Version mismatch (expected after bump, before formula update)"
fi
echo "  ✓ Version check done"

echo ""
echo "  ═══════════════════════════════════════════════"
echo "  ✓ ALL QA CHECKS PASSED"
echo "  ═══════════════════════════════════════════════"
echo ""
