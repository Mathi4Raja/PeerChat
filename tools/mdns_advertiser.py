"""
Simple mDNS advertiser for testing PeerChat discovery.
Run this on your desktop to simulate a peer advertising _peerchat._tcp.local with TXT properties.

Requires: pip install zeroconf

Usage (PowerShell):
python .\tools\mdns_advertiser.py --id TESTID --name "Desktop Test" --port 9000

Press Ctrl+C to stop.
"""
import argparse
import socket
import sys
import time
from zeroconf import ServiceInfo, Zeroconf


def get_local_ip():
    # Try to determine a non-loopback IPv4 address
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # doesn't have to be reachable
        s.connect(('8.8.8.8', 80))
        ip = s.getsockname()[0]
    except Exception:
        ip = '127.0.0.1'
    finally:
        s.close()
    return ip


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--id', default='TESTID', help='peer id (public key fingerprint)')
    parser.add_argument('--name', default='Desktop Test', help='display name')
    parser.add_argument('--port', type=int, default=9000, help='port number')
    args = parser.parse_args()

    ip = get_local_ip()
    print(f'Local IP: {ip}')

    desc = {'id': args.id, 'name': args.name}
    service_type = '_peerchat._tcp.local.'
    service_name = f'peerchat-{args.id}._peerchat._tcp.local.'

    info = ServiceInfo(
        service_type,
        service_name,
        addresses=[socket.inet_aton(ip)],
        port=args.port,
        properties=desc,
        server=socket.gethostname() + '.local.'
    )

    zc = Zeroconf()
    try:
        print('Registering service... Ctrl+C to quit')
        zc.register_service(info)
        while True:
            time.sleep(0.5)
    except KeyboardInterrupt:
        print('Unregistering...')
    finally:
        try:
            zc.unregister_service(info)
        except Exception:
            pass
        zc.close()
        print('Stopped')
