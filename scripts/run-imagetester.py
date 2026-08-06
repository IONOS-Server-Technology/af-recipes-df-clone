#!/usr/bin/env python3
import sys
import os

from ImageBuilder.Util.ImageTester import ImageTester
from ImageBuilder.Util.VmHelpers import VmCreationError
from ImageBuilder.Util.EphemeralIpBlock import EphemeralIpBlock

test_recipe_name = os.environ['RECIPE_NAME']

try:
    with EphemeralIpBlock(test_recipe_name + '_ip') as ip_block:
        tester = ImageTester()
        tester.server_ip = ip_block.ips[0]
        tester.run()
except VmCreationError as exc:
    resp = exc.api_response
    print(f"VmCreationError: status={resp.status_code} url={resp.url}", file=sys.stderr)
    print(f"Response body: {resp.text}", file=sys.stderr)
    raise
