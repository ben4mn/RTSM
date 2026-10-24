"""Protocol provenance for live3 acceptance and retained historical2 reports."""
import hashlib
import json
import math


def protocol_number(value):
    return int(value) if type(value) in (int, float) and math.isfinite(value) and value in (2, 3) else None


def protocol_declared(invocation):
    protocol = protocol_number(invocation.get('protocol'))
    expected = invocation.get('expected_protocol', 2 if protocol == 2 else None)
    return protocol is not None and protocol_number(expected) == protocol


def sealed_protocol(folder, invocation, artifact_files):
    """New3 is bound to exact retained version bytes, never an invocation alone."""
    if not protocol_declared(invocation):
        return False
    path = folder / 'sealed-version.json'
    if not path.exists():
        # Original immutable2 receipts predate this artifact. This path cannot
        # satisfy an explicitly required3 release and never starts a live pair.
        return protocol_number(invocation.get('protocol')) == 2
    try:
        raw = path.read_bytes()
        version = json.loads(raw)
        return (hashlib.sha256(raw).hexdigest() == artifact_files.get('version.json')
                and type(version.get('network_protocol')) is int
                and protocol_number(version.get('network_protocol')) == protocol_number(invocation.get('protocol')))
    except (OSError, ValueError, TypeError, AttributeError):
        return False
