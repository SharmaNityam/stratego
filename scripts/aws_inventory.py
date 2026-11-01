#!/usr/bin/env python3
"""Write an Ansible JSON inventory for the three tagged Stratego AWS nodes."""

import argparse
import json
import pathlib
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', default='stratego-new')
    parser.add_argument('--region', default='ap-southeast-2')
    parser.add_argument('--account', required=True, help='Expected AWS account ID')
    parser.add_argument('--key', required=True, help='Path to the existing SSH private key')
    args = parser.parse_args()
    account = subprocess.check_output([
        'aws', 'sts', 'get-caller-identity', '--profile', args.profile,
        '--region', args.region, '--query', 'Account', '--output', 'text',
    ], text=True).strip()
    if account != args.account:
        raise SystemExit(f'AWS account mismatch: expected {args.account}, got {account}')
    key = pathlib.Path(args.key).expanduser().resolve(strict=True)
    raw = subprocess.check_output([
        'aws', 'ec2', 'describe-instances', '--profile', args.profile,
        '--region', args.region, '--filters', 'Name=tag:Project,Values=stratego',
        'Name=instance-state-name,Values=running', '--output', 'json',
    ], text=True)
    instances = {}
    for reservation in json.loads(raw)['Reservations']:
        for instance in reservation['Instances']:
            tags = {tag['Key']: tag['Value'] for tag in instance.get('Tags', [])}
            name = tags.get('Name')
            if name in instances:
                raise SystemExit(f'Duplicate instance name: {name}')
            instances[name] = instance
    expected = [f'stratego-ha-{number}' for number in range(1, 4)]
    if set(instances) != set(expected):
        raise SystemExit('Expected exactly the three running stratego-ha-1, -2 and -3 instances')
    hostvars = {}
    for number, name in enumerate(expected, 1):
        instance = instances[name]
        if not instance.get('PublicIpAddress') or not instance.get('PrivateIpAddress'):
            raise SystemExit(f'{name} is missing an IP address')
        hostvars[f'node{number}'] = {
            'ansible_host': instance['PublicIpAddress'],
            'private_ip': instance['PrivateIpAddress'],
        }
    inventory = {'all': {
        'vars': {
            'ansible_user': 'ubuntu',
            'ansible_ssh_private_key_file': str(key),
            'ansible_ssh_common_args': '-o StrictHostKeyChecking=accept-new',
        },
        'children': {
            'first': {'hosts': {'node1': hostvars['node1']}},
            'other': {'hosts': {'node2': hostvars['node2'], 'node3': hostvars['node3']}},
        },
    }}
    print(json.dumps(inventory, indent=2))


if __name__ == '__main__':
    main()
