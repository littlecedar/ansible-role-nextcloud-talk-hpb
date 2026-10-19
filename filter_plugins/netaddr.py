# SPDX-FileCopyrightText: 2026 Travis Wichert
#
# SPDX-License-Identifier: AGPL-3.0-or-later

"""Network validation filters for `tasks/validate_config.yml`.

Jinja filters run in the controller process, so these only need the Python
standard library that Ansible itself runs on. ansible-core ships no IP address
filters (they live in `ansible.netcommon`/`ansible.utils`), and this role
deliberately depends on no collection beyond `community.docker`.
"""

from __future__ import annotations

import ipaddress


def nextcloud_talk_hpb_ip_address(value) -> bool:
    """Return True when `value` parses as an IPv4 or IPv6 address."""
    try:
        ipaddress.ip_address(str(value).strip())
    except ValueError:
        return False
    return True


def nextcloud_talk_hpb_ip_network(value) -> bool:
    """Return True when `value` parses as a correctly aligned IPv4/IPv6 CIDR network."""
    try:
        ipaddress.ip_network(str(value).strip(), strict=True)
    except ValueError:
        return False
    return True


def nextcloud_talk_hpb_network_contains(network, address) -> bool:
    """Return True when `address` is inside `network`."""
    try:
        parsed_network = ipaddress.ip_network(str(network).strip(), strict=False)
        parsed_address = ipaddress.ip_address(str(address).strip())
    except ValueError:
        return False
    return parsed_address.version == parsed_network.version and parsed_address in parsed_network


class FilterModule:
    """Expose the filters above to Jinja."""

    def filters(self) -> dict:
        return {
            "nextcloud_talk_hpb_ip_address": nextcloud_talk_hpb_ip_address,
            "nextcloud_talk_hpb_ip_network": nextcloud_talk_hpb_ip_network,
            "nextcloud_talk_hpb_network_contains": nextcloud_talk_hpb_network_contains,
        }
