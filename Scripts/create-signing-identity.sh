#!/bin/bash
#
# Creates a persistent self-signed signing identity for clawd-light.
#
# WHY IT'S NEEDED
# With an ad-hoc signature (`codesign --sign -`) every rebuild produces a binary
# with a different hash, and macOS treats it as a new application: the
# Accessibility and Automation authorizations lapse on every build, while still
# showing the switch as on in Settings. The symptom is a click that stops working
# without saying anything.
#
# With a stable certificate, the signature's "designated requirement" hooks onto
# the identity and not onto the binary's hash: the authorizations survive rebuilds.
#
# WHAT IT DOES, EXACTLY
#  1. generates a self-signed key and certificate valid for 10 years, with the
#     extended key usage "Code Signing", in a temporary folder
#  2. imports them into the user's "login" keychain
#  3. marks them trusted for code signing
#  4. **verifies** that the identity really signs, before declaring success
#
# macOS will ask for the keychain password. No administrator password is needed
# and nothing is installed at system level.
# To undo everything: see the REMOVAL section at the bottom.

set -euo pipefail

NAME="clawd-light Local Signing"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# The script is **idempotent**: if the identity is already there it skips
# creation and goes to the checks, instead of exiting with "nothing to do".
#
# The previous version exited straight away, and that turned the advice "run the
# script again" into a dead end: the identity existed but wasn't authorized yet,
# and re-running never reached the step that was needed. A repair command that
# refuses to repair is worse than no command.
CREATE=1
echo "▸ Checking whether the identity already exists…"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
    echo "  «${NAME}» is already in the keychain: going straight to the checks."
    CREATE=0
fi

if [ "$CREATE" = "1" ]; then

echo "▸ Generating key and certificate…"
cat > "$WORKDIR/openssl.cnf" <<'CNF'
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no

[ dn ]
CN = clawd-light Local Signing

[ ext ]
basicConstraints       = critical,CA:false
keyUsage               = critical,digitalSignature
extendedKeyUsage       = critical,codeSigning
subjectKeyIdentifier   = hash
CNF

openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$WORKDIR/key.pem" \
    -out "$WORKDIR/cert.pem" \
    -days 3650 \
    -config "$WORKDIR/openssl.cnf" 2>/dev/null

# The PKCS#12 has to be produced with the old algorithms, and the password can't
# be empty. Two distinct stumbles, both learned the hard way:
#
#  · OpenSSL 3 by default encrypts the p12 with AES-256 and computes the MAC with
#    SHA-256. macOS's Security framework PKCS#12 parser can't digest them and
#    answers "MAC verification failed during PKCS12 import (wrong password?)" —
#    a message that sends you hunting for a wrong password when the problem is
#    the algorithm. `-legacy` goes back to 3DES/SHA-1, which macOS accepts.
#
#  · With an empty password, "no password" and "a zero-length password" are two
#    different things in the MAC computation, and the two tools choose
#    differently. A real password removes the ambiguity; here it is random and
#    lives only inside the temporary folder, for a few seconds.
#
# `-legacy` doesn't exist in LibreSSL, which is the system openssl: if the flag
# is rejected we retry without it, because there the defaults are already right.
P12_PASSWORD="$(openssl rand -hex 16)"

echo "▸ Packaging the identity…"
if ! openssl pkcs12 -export -legacy \
        -inkey "$WORKDIR/key.pem" \
        -in "$WORKDIR/cert.pem" \
        -out "$WORKDIR/identity.p12" \
        -passout "pass:$P12_PASSWORD" 2>/dev/null; then
    echo "  (openssl doesn't know -legacy: retrying with the defaults)"
    openssl pkcs12 -export \
        -inkey "$WORKDIR/key.pem" \
        -in "$WORKDIR/cert.pem" \
        -out "$WORKDIR/identity.p12" \
        -passout "pass:$P12_PASSWORD" 2>/dev/null
fi

echo "▸ Importing into the keychain (macOS will ask for the password)…"
security import "$WORKDIR/identity.p12" \
    -k "$KEYCHAIN" \
    -P "$P12_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/security

echo "▸ Marking the certificate as trusted for signing…"
# `add-trusted-cert` without -d acts on the user keychain: no administrator
# privileges, no system modifications.
security add-trusted-cert \
    -k "$KEYCHAIN" \
    -p codeSign \
    "$WORKDIR/cert.pem" 2>/dev/null || {
        echo "  Warning: couldn't mark it as trusted."
        echo "  If the check below passes, it isn't a problem."
    }

fi   # end of the creation block

# Without this step, `codesign` doesn't sign: it **hangs**.
#
# `-T /usr/bin/codesign` at import time ought to be enough, and in a keychain
# created on the spot it really is. In the `login` keychain, no: macOS adds a
# "partition list" to the private key, and until codesign is inside that list
# every attempt to use it opens an "allow access?" dialog — which in a
# non-interactive script reaches nobody, and the command hangs forever.
#
# It is the step every signing setup on macOS ends up discovering, always the
# same way: through a command that never returns.
echo "▸ Authorizing codesign to use the key (macOS will ask for the password)…"
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s "$KEYCHAIN" >/dev/null 2>&1 || {
        echo "  That didn't work. It isn't blocking: on the first signing macOS"
        echo "  will ask for permission with a dialog, and «Always Allow» settles"
        echo "  it once and for all."
    }

# The verification is the whole point of this script.
#
# The previous version printed "✓ identity created" right after the import and
# stopped there: when the import failed, the error message scrolled past and the
# next build fell back to the ad-hoc signature **silently**. The user found out it
# hadn't worked only days later, from a click that no longer worked — that is,
# from the symptom hardest to trace back to its cause.
echo "▸ Verifying that the identity really signs…"
printf '#!/bin/sh\nexit 0\n' > "$WORKDIR/probe"
chmod +x "$WORKDIR/probe"

# The signing has to be attempted **with a deadline**, not with a plain `if`.
#
# When the key's authorization is missing, `codesign` doesn't fail: it hangs
# waiting for a dialog. An `if` with no deadline would wait forever, and a script
# that never returns is the worst diagnosis of all — it says less than one that
# fails.
#
# The deadline is done by hand and not with `timeout`, which macOS doesn't ship.
codesign --force --sign "$NAME" --timestamp=none "$WORKDIR/probe" \
    >"$WORKDIR/out" 2>"$WORKDIR/error" &
SIGN_PID=$!

for _ in $(seq 1 20); do
    kill -0 "$SIGN_PID" 2>/dev/null || break
    sleep 1
done

if kill -0 "$SIGN_PID" 2>/dev/null; then
    kill "$SIGN_PID" 2>/dev/null || true
    echo
    echo "⏳ codesign was left waiting: there is a macOS dialog on screen."
    echo
    echo "  It's asking whether to allow access to the key just created."
    echo "  Press «Always Allow» — not «Allow», which asks again every time."
    echo
    echo "  Then run it again:  ./Scripts/create-signing-identity.sh"
    echo "  (the identity is already there: it will recognize the situation"
    echo "   and won't recreate it)"
    exit 1
fi

if ! wait "$SIGN_PID"; then
    echo
    echo "✗ The identity is in the keychain but codesign can't use it."
    echo
    sed 's/^/  /' "$WORKDIR/error"
    echo
    echo "  Open Keychain Access, look for «${NAME}», double-click →"
    echo "  Access Control → Code Signing: «Always Trust»."
    echo
    echo "  Or remove it and stay with the ad-hoc signature: see REMOVAL below."
    exit 1
fi

# The check goes through a file, and **not** through `… | grep -q`.
#
# `grep -q` exits at the first match and closes the pipe. `codesign` still has
# five lines to write, receives SIGPIPE, exits with 141, and `pipefail` fails the
# pipeline **even though the match was there**. Worse: it depends on who gets
# there first, so it works one time in two. It has already produced a
# "✗ the signature doesn't appear to be issued by…" on a perfectly valid signature.
codesign --display --verbose=2 "$WORKDIR/probe" >"$WORKDIR/details" 2>&1 || true

if ! grep -q "Authority=$NAME" "$WORKDIR/details"; then
    echo
    echo "✗ The signing succeeded but doesn't appear to be issued by «${NAME}»."
    echo
    sed 's/^/  /' "$WORKDIR/details"
    echo
    echo "  Don't trust this outcome: check the keychain again."
    exit 1
fi

echo
echo "✓ Identity «${NAME}» created and verified: codesign uses it."
echo
echo "  Now rebuild:  ./Scripts/build-app.sh"
echo
echo "  The Accessibility and Automation authorizations will have to be granted"
echo "  ONE LAST time after the first build signed this way. From then on they"
echo "  survive rebuilds."
echo
echo "  REMOVAL: Keychain Access → look for «${NAME}» → delete the certificate"
echo "  and the key. The build script will automatically go back to ad-hoc signing."
