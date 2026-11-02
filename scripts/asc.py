#!/usr/bin/env python3
"""App Store Connect API from the Mac: a signed token and plain requests.

The key (a team key with the App Manager role) lives only in the Mac's Keychain, item "Ares Empire App Store Connect
API key": the password is the base64 of Apple's .p8 file, the account is the key ID, the comment holds the issuer ID.
Nothing about the key is ever written to a file. Uses only the standard library and openssl (no extra packages).

  python3 scripts/asc.py get '/v1/apps?filter[bundleId]=de.ares-empire.aresium'
  python3 scripts/asc.py post /v1/betaGroups body.json
  python3 scripts/asc.py patch /v1/betaAppLocalizations/<id> body.json
  python3 scripts/asc.py delete /v1/betaGroups/<id>/relationships/builds body.json
"""
import base64
import json
import os
import re
import subprocess
import sys
import time

KEYCHAIN_ITEM = "Ares Empire App Store Connect API key"
API = "https://api.appstoreconnect.apple.com"


def keychain():
    """The key's ID, the issuer ID and the .p8's bytes, from the Keychain."""
    attributes = subprocess.run(["security", "find-generic-password", "-s", KEYCHAIN_ITEM],
                                capture_output=True, text=True, check=True).stdout
    key_id = re.search(r'"acct"<blob>="([^"]+)"', attributes).group(1)
    issuer = re.search(r'issuer=([0-9a-f-]{36})', attributes).group(1)
    secret = subprocess.run(["security", "find-generic-password", "-s", KEYCHAIN_ITEM, "-w"],
                            capture_output=True, text=True, check=True).stdout.strip()
    return key_id, issuer, base64.b64decode(secret)


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(signature):
    """openssl gives an ES256 signature as DER (SEQUENCE of two INTEGERs); a JWT wants r and s, 32 bytes each."""
    assert signature[0] == 0x30
    index = 2 if signature[1] < 0x80 else 2 + (signature[1] & 0x7F)
    parts = []
    for _ in range(2):
        assert signature[index] == 0x02
        length = signature[index + 1]
        value = signature[index + 2:index + 2 + length]
        parts.append(value.lstrip(b"\x00").rjust(32, b"\x00"))
        index += 2 + length
    return parts[0] + parts[1]


def token():
    """A token valid for 20 minutes (Apple's limit). The key reaches openssl through a pipe, never a file."""
    key_id, issuer, key = keychain()
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    payload = b64url(json.dumps({"iss": issuer, "iat": now, "exp": now + 1200,
                                 "aud": "appstoreconnect-v1"}).encode())
    signing_input = f"{header}.{payload}".encode()
    read_end, write_end = os.pipe()
    os.write(write_end, key)
    os.close(write_end)
    try:
        signature = subprocess.run(["openssl", "dgst", "-sha256", "-sign", f"/dev/fd/{read_end}"],
                                   input=signing_input, capture_output=True, check=True,
                                   pass_fds=(read_end,)).stdout
    finally:
        os.close(read_end)
    return f"{header}.{payload}.{b64url(der_to_raw(signature))}"


def request(method, path, body=None):
    """One call; returns (status, parsed JSON or None). Errors come back as their status and Apple's JSON.

    Through curl, which trusts the Mac's own certificates (python.org's Python has none of its own). The token goes to
    curl in a config read from stdin, so it never shows in the process list; the body goes through a pipe."""
    config = [f'header = "Authorization: Bearer {token()}"', 'header = "Content-Type: application/json"']
    pass_fds = ()
    read_end = None
    if body is not None:
        read_end, write_end = os.pipe()
        os.write(write_end, json.dumps(body).encode())
        os.close(write_end)
        config.append(f'data-binary = "@/dev/fd/{read_end}"')
        pass_fds = (read_end,)
    try:
        result = subprocess.run(["curl", "-sS", "-g", "-K", "-", "-X", method.upper(), "-w", "\n%{http_code}",
                                 API + path],
                                input="\n".join(config).encode(), capture_output=True, check=True,
                                pass_fds=pass_fds, timeout=90)
    finally:
        if read_end is not None:
            os.close(read_end)
    raw, _, status = result.stdout.decode().rpartition("\n")
    return int(status), (json.loads(raw) if raw.strip() else None)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    method, path = argv[1], argv[2]
    body = json.load(open(argv[3])) if len(argv) > 3 else None
    status, answer = request(method, path, body)
    print(status, file=sys.stderr)
    if answer is not None:
        print(json.dumps(answer, indent=2, ensure_ascii=False))
    return 0 if 200 <= status < 300 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
