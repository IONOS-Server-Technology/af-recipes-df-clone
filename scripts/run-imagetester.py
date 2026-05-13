#!/usr/bin/env python3
import sys

from ImageBuilder.Util.ImageTester import ImageTester
from ImageBuilder.Util.VmHelpers import VmCreationError

try:
    ImageTester().run()
except VmCreationError as exc:
    resp = exc.api_response
    print(f"VmCreationError: status={resp.status_code} url={resp.url}", file=sys.stderr)
    print(f"Response body: {resp.text}", file=sys.stderr)
    raise
