#!/usr/bin/env bash
# Offline checks for templates/lb-port-redirect.sh.tpl.
# Renders the template with service_port=22 / server_port=2022 and runs it against stubbed
# curl, iptables, and sleep on PATH. Verifies: rule inserted once on first run, not duplicated
# on second run, non-zero exit when the metadata lookup fails.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="${ROOT}/templates/lb-port-redirect.sh.tpl"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

SCRIPT="${WORKDIR}/lb-port-redirect-22.sh"
sed -e 's/\${service_port}/22/g' -e 's/\${server_port}/2022/g' "${TEMPLATE}" > "${SCRIPT}"
chmod 0755 "${SCRIPT}"
if grep -q '\${' "${SCRIPT}"; then
  echo "FAIL: unrendered template markers remain in script" >&2
  exit 1
fi

# Stubs. iptables keeps a fake nat PREROUTING table in STUB_RULES, a fake filter INPUT table in
# STUB_INPUT, and logs every call.
mkdir -p "${WORKDIR}/bin"
export STUB_RULES="${WORKDIR}/rules" STUB_INPUT="${WORKDIR}/input" STUB_LOG="${WORKDIR}/iptables.log"
: > "${STUB_RULES}"; : > "${STUB_INPUT}"; : > "${STUB_LOG}"
cat > "${WORKDIR}/bin/curl" <<'STUB'
#!/usr/bin/env bash
if [ "${STUB_CURL_FAIL:-0}" = "1" ]; then exit 22; fi
printf '10.0.0.5'
STUB
cat > "${WORKDIR}/bin/iptables" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "${STUB_LOG}"
if [ "$1" = "-t" ]; then
  [ "$2" = "nat" ] || { echo "stub: unexpected table $2" >&2; exit 2; }
  table="${STUB_RULES}"; shift 2
  [ "$2" = "PREROUTING" ] || { echo "stub: expected PREROUTING chain" >&2; exit 2; }
else
  table="${STUB_INPUT}"
  [ "$2" = "INPUT" ] || { echo "stub: expected INPUT chain" >&2; exit 2; }
fi
case "$1" in
  -C) rule="${*:3}"; grep -qxF -- "${rule}" "${table}" ;;
  -I) [ "$3" = "1" ] || { echo "stub: expected insert at position 1" >&2; exit 2; }
      rule="${*:4}"
      printf '%s\n' "${rule}" | cat - "${table}" > "${table}.new"
      mv "${table}.new" "${table}" ;;
  *) echo "stub: unexpected iptables op $1" >&2; exit 2 ;;
esac
STUB
printf '#!/usr/bin/env bash\nexit 0\n' > "${WORKDIR}/bin/sleep"
chmod 0755 "${WORKDIR}/bin/"*
export PATH="${WORKDIR}/bin:${PATH}"

EXPECTED='-p tcp --dport 22 ! -d 10.0.0.5 -j REDIRECT --to-ports 2022'

# 1) First run inserts the rule once, at position 1, ahead of anything else.
"${SCRIPT}"
if [ "$(wc -l < "${STUB_RULES}")" -ne 1 ] || ! grep -qxF -- "${EXPECTED}" "${STUB_RULES}"; then
  echo "FAIL: expected exactly one rule '${EXPECTED}', got:" >&2; cat "${STUB_RULES}" >&2
  exit 1
fi
if [ "$(grep -c -- '-I PREROUTING 1 ' "${STUB_LOG}")" -ne 1 ]; then
  echo "FAIL: expected one insert call" >&2; cat "${STUB_LOG}" >&2
  exit 1
fi
echo "OK: first run inserts rule once"

# 1b) First run also accepts the redirected traffic in filter INPUT (COS INPUT policy is DROP).
EXPECTED_INPUT='-p tcp --dport 2022 -j ACCEPT'
if [ "$(wc -l < "${STUB_INPUT}")" -ne 1 ] || ! grep -qxF -- "${EXPECTED_INPUT}" "${STUB_INPUT}"; then
  echo "FAIL: expected exactly one INPUT rule '${EXPECTED_INPUT}', got:" >&2; cat "${STUB_INPUT}" >&2
  exit 1
fi
echo "OK: first run accepts server_port in INPUT"

# 2) Second run is idempotent.
"${SCRIPT}"
if [ "$(wc -l < "${STUB_RULES}")" -ne 1 ] || [ "$(grep -c -- '-I PREROUTING 1 ' "${STUB_LOG}")" -ne 1 ]; then
  echo "FAIL: second run duplicated the rule" >&2; cat "${STUB_LOG}" >&2
  exit 1
fi
if [ "$(wc -l < "${STUB_INPUT}")" -ne 1 ] || [ "$(grep -c -- '-I INPUT 1 ' "${STUB_LOG}")" -ne 1 ]; then
  echo "FAIL: second run duplicated the INPUT rule" >&2; cat "${STUB_LOG}" >&2
  exit 1
fi
echo "OK: second run does not duplicate rules"

# 3) Metadata lookup failure exits non-zero and installs nothing.
: > "${STUB_RULES}"; : > "${STUB_INPUT}"; : > "${STUB_LOG}"
if STUB_CURL_FAIL=1 "${SCRIPT}" 2>/dev/null; then
  echo "FAIL: metadata failure should exit non-zero" >&2
  exit 1
fi
if [ -s "${STUB_RULES}" ] || [ -s "${STUB_INPUT}" ] || [ -s "${STUB_LOG}" ]; then
  echo "FAIL: no iptables call expected when metadata lookup fails" >&2
  exit 1
fi
echo "OK: metadata failure exits non-zero without touching iptables"

echo "All lb-port-redirect checks passed."
