#!/usr/bin/env python3
import sys
import os

from ImageBuilder.Util.ImageTester import ImageTester
from ImageBuilder.Util.VmHelpers import VmCreationError
from ImageBuilder.Util.EphemeralIpBlock import EphemeralIpBlock

def main():
    test_recipe_name = os.environ['RECIPE_NAME']
    run_id = os.environ.get('GITHUB_RUN_ID', 'local')
    run_attempt = os.environ.get('GITHUB_RUN_ATTEMPT', '1')
    ip_block_name = f'{test_recipe_name}_{run_id}_{run_attempt}_ip'

    try:
        with EphemeralIpBlock(ip_block_name) as ip_block:
            tester = ImageTester()
            tester.server_ip = ip_block.ips[0]
            tester.run()
    except VmCreationError as exc:
        resp = exc.api_response
        print(f"VmCreationError: status={resp.status_code} url={resp.url}", file=sys.stderr)
        print(f"Response body: {resp.text}", file=sys.stderr)
        raise

if __name__ == '__main__':
    main()