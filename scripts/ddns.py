#!/usr/bin/env python3
"""
Porkbun Dynamic DNS Updater

Updates a DNS A record on Porkbun when your public IP changes.
Designed to run continuously in a Docker container.
"""

import os
import sys
import time
import requests

# Configuration from environment
API_KEY = os.environ.get('PORKBUN_API_KEY', '')
SECRET_KEY = os.environ.get('PORKBUN_SECRET_KEY', '')
DOMAIN = os.environ.get('PORKBUN_DOMAIN', '')
SUBDOMAIN = os.environ.get('PORKBUN_SUBDOMAIN', '@')
INTERVAL = int(os.environ.get('DDNS_INTERVAL', 300))

PORKBUN_API = 'https://api.porkbun.com/api/json/v3'
IP_SERVICES = [
    'https://api.ipify.org',
    'https://icanhazip.com',
    'https://ifconfig.me/ip',
]


def get_public_ip():
    """Get current public IP address."""
    for service in IP_SERVICES:
        try:
            response = requests.get(service, timeout=10)
            if response.status_code == 200:
                return response.text.strip()
        except requests.RequestException:
            continue
    return None


def get_current_record():
    """Get the current DNS A record from Porkbun."""
    url = f'{PORKBUN_API}/dns/retrieveByNameType/{DOMAIN}/A/{SUBDOMAIN}'
    payload = {
        'apikey': API_KEY,
        'secretapikey': SECRET_KEY,
    }
    try:
        response = requests.post(url, json=payload, timeout=30)
        data = response.json()
        if data.get('status') == 'SUCCESS' and data.get('records'):
            return data['records'][0].get('content')
    except requests.RequestException as e:
        print(f'Error getting current record: {e}', flush=True)
    return None


def update_dns_record(ip):
    """Update the DNS A record on Porkbun."""
    url = f'{PORKBUN_API}/dns/editByNameType/{DOMAIN}/A/{SUBDOMAIN}'
    payload = {
        'apikey': API_KEY,
        'secretapikey': SECRET_KEY,
        'content': ip,
        'ttl': '300',
    }
    try:
        response = requests.post(url, json=payload, timeout=30)
        data = response.json()
        if data.get('status') == 'SUCCESS':
            return True
        else:
            print(f'Porkbun API error: {data.get("message", "Unknown error")}', flush=True)
    except requests.RequestException as e:
        print(f'Error updating record: {e}', flush=True)
    return False


def create_dns_record(ip):
    """Create a new DNS A record on Porkbun (if it doesn't exist)."""
    url = f'{PORKBUN_API}/dns/create/{DOMAIN}'
    payload = {
        'apikey': API_KEY,
        'secretapikey': SECRET_KEY,
        'type': 'A',
        'name': SUBDOMAIN if SUBDOMAIN != '@' else '',
        'content': ip,
        'ttl': '300',
    }
    try:
        response = requests.post(url, json=payload, timeout=30)
        data = response.json()
        if data.get('status') == 'SUCCESS':
            return True
        else:
            print(f'Porkbun API error: {data.get("message", "Unknown error")}', flush=True)
    except requests.RequestException as e:
        print(f'Error creating record: {e}', flush=True)
    return False


def main():
    """Main loop - check and update IP periodically."""
    # Validate configuration
    if not all([API_KEY, SECRET_KEY, DOMAIN]):
        print('Error: PORKBUN_API_KEY, PORKBUN_SECRET_KEY, and PORKBUN_DOMAIN must be set', flush=True)
        sys.exit(1)

    record_name = f'{SUBDOMAIN}.{DOMAIN}' if SUBDOMAIN != '@' else DOMAIN
    print(f'Porkbun DDNS started for {record_name}', flush=True)
    print(f'Update interval: {INTERVAL} seconds', flush=True)

    last_ip = None

    while True:
        current_ip = get_public_ip()

        if current_ip is None:
            print('Could not determine public IP, retrying...', flush=True)
            time.sleep(60)
            continue

        if current_ip != last_ip:
            print(f'IP change detected: {last_ip} -> {current_ip}', flush=True)

            # Check if record exists
            existing_ip = get_current_record()

            if existing_ip is None:
                # Record doesn't exist, create it
                print(f'Creating new A record for {record_name} -> {current_ip}', flush=True)
                if create_dns_record(current_ip):
                    print(f'Successfully created DNS record', flush=True)
                    last_ip = current_ip
            elif existing_ip != current_ip:
                # Record exists but has different IP, update it
                print(f'Updating A record for {record_name}: {existing_ip} -> {current_ip}', flush=True)
                if update_dns_record(current_ip):
                    print(f'Successfully updated DNS record', flush=True)
                    last_ip = current_ip
            else:
                # Record exists and matches
                print(f'DNS record already up to date: {current_ip}', flush=True)
                last_ip = current_ip

        time.sleep(INTERVAL)


if __name__ == '__main__':
    main()
