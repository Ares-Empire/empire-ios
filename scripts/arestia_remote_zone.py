#!/usr/bin/env python3
"""Set the single Arestia ATS exception in a processed Info.plist."""

import os
from pathlib import Path
import plistlib
import re
import sys


DEBUG_ZONE = "home.example.net"
LABEL = r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?"


def read_zone(*, debug=False):
    override = os.environ.get("ARESTIA_REMOTE_ZONE_FILE")
    if override == "":
        raise ValueError("ARESTIA_REMOTE_ZONE_FILE is set but empty")
    path = Path(override) if override is not None else Path.home() / ".config/arestia/remote-zone"
    try:
        with path.open("rb") as file:
            raw = file.read(256)
    except FileNotFoundError:
        if debug:
            return DEBUG_ZONE
        raise ValueError("remote zone file is missing; set ARESTIA_REMOTE_ZONE_FILE or create ~/.config/arestia/remote-zone")
    except OSError:
        raise ValueError("remote zone file could not be read")
    zone = raw.removesuffix(b"\n").removesuffix(b"\r")
    if len(zone) > 253 or not re.fullmatch(rf"{LABEL}(?:\.{LABEL})+".encode("ascii"), zone):
        raise ValueError("remote zone file must contain one lowercase DNS name with at least two labels")
    # A DNS name ends in a nonnumeric label. This also rules out IPv4 literals.
    if zone.rsplit(b".", 1)[1].isdigit():
        raise ValueError("remote zone file must contain a DNS name, not an IP address")
    return zone.decode("ascii")


def ats_settings(zone):
    return {"NSExceptionDomains": {zone: {"NSIncludesSubdomains": True,
                                          "NSExceptionAllowsInsecureHTTPLoads": True}}}


def main():
    try:
        plist = Path(sys.argv[1])
        zone = read_zone(debug=os.environ.get("CONFIGURATION") == "Debug")
        data = plistlib.loads(plist.read_bytes())
        data["NSAppTransportSecurity"] = ats_settings(zone)
        updated = plistlib.dumps(data, fmt=plistlib.FMT_BINARY)
        temporary = plist.with_name(plist.name + ".arestia-ats")
        temporary.write_bytes(updated)
        temporary.replace(plist)
    except ValueError as error:
        print(f"error: Arestia ATS: {error}", file=sys.stderr)
        return 1
    except OSError:
        print("error: Arestia ATS: could not update the processed Info.plist", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
