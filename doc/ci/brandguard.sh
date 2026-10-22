#!/usr/bin/env sh
# Generic CI step: validate brands, keep a JSON report, propagate the exit code.
#
#   BRAND=acme STRICT=1 ./brandguard.sh
#
# Exit codes: 0 passed, 1 validation failed, 2 configuration/usage error.
set -u

REPORT="${BRANDGUARD_REPORT:-brandguard-report.json}"
if [ -n "${BRAND:-}" ]; then
  set -- --brand "$BRAND"
else
  set -- --all
fi
if [ "${STRICT:-0}" = "1" ]; then
  set -- "$@" --strict
fi

dart run brandguard_flutter check "$@" --format json > "$REPORT"
status=$?

# Human-readable log next to the machine-readable report.
if [ "$status" -ne 2 ]; then
  dart run brandguard_flutter check "$@" --no-color --quiet
fi

echo "BrandGuard exit code: $status (report: $REPORT)"
exit "$status"
