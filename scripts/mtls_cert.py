"""Resolve mTLS client cert/key CLI args into file paths for requests' ``cert=``.

``call-compose.py`` and ``probe-bootstrap.py`` share this so the live prod-mode
recipe test can present the recipes-pipeline PUKI client certificate to an af-api
mTLS ingress. Both real-cluster legs need one; the plain dev-mode run against the
ephemeral af-api NodePort does not, so both arguments are optional and omitting
them sends no client cert.
"""
from __future__ import annotations

from pathlib import Path


def resolve_client_cert(cert: str | None, key: str | None) -> tuple[str, str] | None:
    """Return a ``(cert_path, key_path)`` tuple for requests' ``cert=`` kwarg.

    Both arguments must be paths to existing PEM files. Returns ``None`` when
    neither is supplied. Raises ``ValueError`` if only one of the pair is given,
    or if either path does not exist — requests would otherwise fail deep in the
    TLS layer with an opaque SSL error instead of naming the missing file.
    """
    if cert is None and key is None:
        return None
    if cert is None or key is None:
        raise ValueError("--client-cert and --client-key must be supplied together")
    for label, value in (("--client-cert", cert), ("--client-key", key)):
        if not Path(value).is_file():
            raise ValueError(f"{label}: no such file: {value}")
    return (cert, key)
