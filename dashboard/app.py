"""
Homelab Dashboard - Central landing page for all services.
"""
import os
from datetime import timedelta
from flask import Flask, render_template, request
import requests

app = Flask(__name__)

# Configuration from environment
PROMETHEUS_URL = os.getenv('PROMETHEUS_URL', 'http://prometheus:9090')
DASHBOARD_HOST = os.getenv('DASHBOARD_HOST', '')  # Empty = use request host

# Service definitions
SERVICES = [
    {'name': 'Jellyfin', 'port': 8096, 'icon': 'film', 'desc': 'Media Server', 'color': '#00a4dc'},
    {'name': 'Home Assistant', 'port': 8123, 'icon': 'home', 'desc': 'Home Automation', 'color': '#41bdf5'},
    {'name': 'Transmission', 'port': 9091, 'icon': 'download', 'desc': 'Torrent Client', 'color': '#b50d0d'},
    {'name': 'Nextcloud', 'port': 8080, 'icon': 'cloud', 'desc': 'Cloud Storage', 'color': '#0082c9'},
    {'name': 'Syncthing', 'port': 8384, 'icon': 'sync', 'desc': 'File Sync', 'color': '#0891d1'},
    {'name': 'MeshChat', 'port': 8000, 'icon': 'comments', 'desc': 'Mesh Network Chat', 'color': '#6366f1'},
    {'name': 'Grafana', 'port': 3000, 'icon': 'chart-line', 'desc': 'Monitoring Dashboards', 'color': '#f46800'},
    {'name': 'Prometheus', 'port': 9090, 'icon': 'database', 'desc': 'Metrics Store', 'color': '#e6522c'},
    {'name': 'i2pd Console', 'port': 7070, 'icon': 'user-secret', 'desc': 'I2P Router (SSH Tunnel)', 'color': '#9333ea', 'localhost_only': True},
]


def get_host():
    """Get the host to use for service URLs."""
    if DASHBOARD_HOST:
        return DASHBOARD_HOST
    # Extract hostname without port from request
    host = request.host.split(':')[0]
    return host


def query_prometheus(query):
    """Execute a PromQL query and return the result."""
    try:
        response = requests.get(
            f'{PROMETHEUS_URL}/api/v1/query',
            params={'query': query},
            timeout=5
        )
        response.raise_for_status()
        data = response.json()
        if data['status'] == 'success' and data['data']['result']:
            return float(data['data']['result'][0]['value'][1])
    except Exception as e:
        app.logger.warning(f"Prometheus query failed: {e}")
    return None


def get_system_stats():
    """Fetch system stats from Prometheus/node-exporter."""
    stats = {}

    # CPU Usage (percentage)
    cpu = query_prometheus(
        '100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[1m])) * 100)'
    )
    stats['cpu'] = round(cpu, 1) if cpu is not None else None

    # Memory Usage (percentage)
    mem_query = '100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))'
    mem = query_prometheus(mem_query)
    stats['memory'] = round(mem, 1) if mem is not None else None

    # Memory Total (GB)
    mem_total = query_prometheus('node_memory_MemTotal_bytes')
    stats['memory_total_gb'] = round(mem_total / (1024**3), 1) if mem_total else None

    # Disk Usage - root filesystem (percentage)
    disk = query_prometheus(
        '100 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100)'
    )
    stats['disk'] = round(disk, 1) if disk is not None else None

    # Disk Total (GB)
    disk_total = query_prometheus('node_filesystem_size_bytes{mountpoint="/"}')
    stats['disk_total_gb'] = round(disk_total / (1024**3), 1) if disk_total else None

    # Uptime
    uptime_seconds = query_prometheus('node_time_seconds - node_boot_time_seconds')
    if uptime_seconds:
        uptime = timedelta(seconds=int(uptime_seconds))
        days = uptime.days
        hours, remainder = divmod(uptime.seconds, 3600)
        minutes, _ = divmod(remainder, 60)
        stats['uptime'] = f"{days}d {hours}h {minutes}m"
    else:
        stats['uptime'] = None

    return stats


@app.route('/')
def index():
    """Homepage with service links and system stats."""
    host = get_host()
    services = []
    for s in SERVICES:
        service = {**s}
        if s.get('localhost_only'):
            # For localhost-only services, link to SSH tunnel guide
            service['url'] = '/ssh-tunnel'
        else:
            service['url'] = f'http://{host}:{s["port"]}'
        services.append(service)
    stats = get_system_stats()
    return render_template('index.html', services=services, stats=stats, host=host)


@app.route('/wireguard')
def wireguard():
    """WireGuard setup overview."""
    return render_template('wireguard/index.html')


@app.route('/wireguard/<platform>')
def wireguard_platform(platform):
    """Platform-specific WireGuard setup instructions."""
    valid_platforms = ['android', 'windows', 'linux', 'macos']
    if platform not in valid_platforms:
        return render_template('wireguard/index.html'), 404

    wg_server = os.getenv('WG_SERVERURL', 'vpn.example.com')
    wg_port = os.getenv('WG_SERVERPORT', '51820')

    return render_template(
        f'wireguard/{platform}.html',
        wg_server=wg_server,
        wg_port=wg_port
    )


@app.route('/ssh-tunnel')
def ssh_tunnel():
    """SSH tunnel setup overview."""
    return render_template('ssh-tunnel/index.html')


@app.route('/ssh-tunnel/<platform>')
def ssh_tunnel_platform(platform):
    """Platform-specific SSH tunnel setup instructions."""
    valid_platforms = ['linux', 'macos', 'windows']
    if platform not in valid_platforms:
        return render_template('ssh-tunnel/index.html'), 404

    # Get SSH connection info (user can customize via env)
    ssh_host = os.getenv('SSH_HOST', 'homelab')
    ssh_user = os.getenv('SSH_USER', 'admin')

    return render_template(
        f'ssh-tunnel/{platform}.html',
        ssh_host=ssh_host,
        ssh_user=ssh_user
    )


@app.route('/health')
def health():
    """Health check endpoint."""
    return {'status': 'healthy'}


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80, debug=True)
