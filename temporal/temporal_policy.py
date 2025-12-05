#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SEER Temporal Policy Engine
Network-wide website blocking via DNS interception with time-based scheduling
Author: PatrickReyes-111
Date: 2025-11-14
"""

import json
import subprocess
import os
import signal
import time
import sqlite3
from http.server import BaseHTTPRequestHandler, HTTPServer
from datetime import datetime
from pathlib import Path

# Configuration
HOST_NAME = "127.0.0.1"
SERVER_PORT = 1889
POLICIES = []

# Database Configuration
# Using absolute path to ensure consistency regardless of user context
DB_PATH = "/home/admin/.node-red/seer_database/seer.db"
DB_TABLE = "temporal_policy"

def ensure_db_initialized():
    """Ensure database and table exist"""
    try:
        # Create directory if it doesn't exist
        db_dir = os.path.dirname(DB_PATH)
        if not os.path.exists(db_dir):
            os.makedirs(db_dir, exist_ok=True)
            print("[DB] Created database directory: %s" % db_dir)
        
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        # Check if table exists and verify schema
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='temporal_policy'")
        if not cursor.fetchone():
            # Create table with key-value schema
            cursor.execute("""
                CREATE TABLE temporal_policy (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    key TEXT UNIQUE,
                    value TEXT
                )
            """)
            print("[DB] Created temporal_policy table")
        
        conn.commit()
        conn.close()
        print("[DB] ✅ Database initialized successfully")
        return True
    except Exception as e:
        print("[DB ERROR] Failed to initialize database: %s" % str(e))
        return False


def kill_process_on_port(port):
    """Kill any process using the specified port"""
    try:
        result = subprocess.run(
            ['lsof', '-ti', ':%d' % port],
            capture_output=True,
            text=True,
            check=False
        )

        if result.stdout.strip():
            pids = result.stdout.strip().split('\n')
            for pid in pids:
                try:
                    pid_num = int(pid.strip())
                    print("[CLEANUP] Killing process %d on port %d" % (pid_num, port))
                    os.kill(pid_num, signal.SIGKILL)
                except (ValueError, ProcessLookupError):
                    pass
            time.sleep(1)
            print("[CLEANUP] Port %d freed" % port)
            return True
    except FileNotFoundError:
        pass

    try:
        result = subprocess.run(
            ['fuser', '-k', '%d/tcp' % port],
            capture_output=True,
            check=False
        )
        if result.returncode == 0:
            time.sleep(1)
            print("[CLEANUP] Port %d freed using fuser" % port)
            return True
    except FileNotFoundError:
        pass

    return False


# ==================== DATABASE FUNCTIONS ====================

def get_db_connection():
    """Get SQLite database connection"""
    try:
        conn = sqlite3.connect(DB_PATH, timeout=5)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL")  # Better concurrency
        return conn
    except sqlite3.Error as e:
        print("[DB ERROR] Failed to connect: %s" % str(e))
        return None


def save_blocked_website_to_db(domain, device_mac="BOARD_WIDE"):
    """Save blocked website to database"""
    try:
        conn = get_db_connection()
        if not conn:
            print("[DB ERROR] Could not get database connection")
            return False
        
        cursor = conn.cursor()
        
        try:
            # Store as key='blocked_domain:domain' and value='1' for active
            cursor.execute("""
                INSERT OR REPLACE INTO temporal_policy (key, value)
                VALUES (?, ?)
            """, ("blocked_domain:" + domain, "1"))
            
            conn.commit()
            print("[DB] ✅ Saved to database: %s" % domain)
            return True
        except sqlite3.IntegrityError as e:
            print("[DB ERROR] Integrity error: %s" % str(e))
            conn.rollback()
            return False
        except Exception as e:
            print("[DB ERROR] Query error: %s" % str(e))
            conn.rollback()
            return False
        finally:
            conn.close()
    except Exception as e:
        print("[DB ERROR] Failed to save: %s" % str(e))
        return False


def remove_blocked_website_from_db(domain):
    """Remove blocked website from database (mark as inactive)"""
    try:
        conn = get_db_connection()
        if not conn:
            print("[DB ERROR] Could not get database connection")
            return False
        
        cursor = conn.cursor()
        try:
            # Update value to '0' to mark as inactive
            cursor.execute("""
                UPDATE temporal_policy
                SET value = ?
                WHERE key = ?
            """, ("0", "blocked_domain:" + domain))
            
            if cursor.rowcount == 0:
                print("[DB] Website not found in database: %s" % domain)
            
            conn.commit()
            print("[DB] ✅ Removed from database: %s" % domain)
            return True
        except Exception as e:
            print("[DB ERROR] Query error: %s" % str(e))
            conn.rollback()
            return False
        finally:
            conn.close()
    except Exception as e:
        print("[DB ERROR] Failed to remove: %s" % str(e))
        return False


def load_blocked_websites_from_db():
    """Load all active blocked websites from database"""
    try:
        conn = get_db_connection()
        if not conn:
            print("[DB ERROR] Could not get database connection")
            return []
        
        cursor = conn.cursor()
        try:
            cursor.execute("""
                SELECT key, value 
                FROM temporal_policy 
                WHERE key LIKE 'blocked_domain:%' AND value = '1'
                ORDER BY key
            """)
            
            rows = cursor.fetchall()
            websites = [row[0].replace('blocked_domain:', '') for row in rows]
            print("[DB] ✅ Loaded %d blocked websites from database" % len(websites))
            return websites
        except Exception as e:
            print("[DB ERROR] Query error: %s" % str(e))
            return []
        finally:
            conn.close()
    except Exception as e:
        print("[DB ERROR] Failed to load: %s" % str(e))
        return []


def apply_block_website(domain):
    """Apply block to /etc/hosts and DNSMasq without HTTP handler"""
    try:
        # Method 1: Add to /etc/hosts (for Pi itself)
        with open('/etc/hosts', 'r') as f:
            content = f.read()
            if "127.0.0.1 %s" % domain in content or "127.0.0.1 www.%s" % domain in content:
                print("[INFO] %s already in /etc/hosts" % domain)
            else:
                with open('/etc/hosts', 'a') as f:
                    f.write("\n# SEER Policy %s\n" % datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
                    f.write("127.0.0.1 %s\n" % domain)
                    f.write("127.0.0.1 www.%s\n" % domain)

        # Method 2: Add to DNSMasq (for all network clients)
        dnsmasq_file = "/etc/dnsmasq.d/blocked-sites.conf"
        
        # Read current blocks
        blocked_domains = set()
        try:
            with open(dnsmasq_file, 'r') as f:
                for line in f:
                    if line.startswith("address=/"):
                        blocked_domains.add(line.strip())
        except:
            pass
        
        # Add new blocks (including wildcard for all subdomains)
        new_entries = [
            "address=/%s/127.0.0.1" % domain,
            "address=/.%s/127.0.0.1" % domain  # Wildcard for all subdomains
        ]
        
        for entry in new_entries:
            blocked_domains.add(entry)
        
        # Write back to file
        with open(dnsmasq_file, 'w') as f:
            f.write("# SEER Temporal Policy - Blocked Domains\n")
            f.write("# This file is managed by temporal_policy.py\n")
            f.write("# Last updated: %s\n\n" % datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
            for entry in sorted(blocked_domains):
                f.write(entry + "\n")
        
        # Restart DNSMasq to apply changes
        subprocess.run(['systemctl', 'restart', 'dnsmasq'],
                     check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        
        print("[STARTUP] Applied block: %s" % domain)
        return True
    except Exception as e:
        print("[STARTUP ERROR] Failed to apply block %s: %s" % (domain, str(e)))
        return False


def load_and_apply_blocked_websites():
    """Load blocked websites from database and apply them on startup"""
    print("\n[STARTUP] Loading blocked websites from database...")
    websites = load_blocked_websites_from_db()
    
    if not websites:
        print("[STARTUP] No blocked websites found in database")
        return
    
    print("[STARTUP] Applying %d blocked websites..." % len(websites))
    
    for website in websites:
        print("[STARTUP] Processing: %s" % website)
        if apply_block_website(website):
            # Add to POLICIES list
            existing = any(p.get("destination") == website for p in POLICIES)
            if not existing:
                POLICIES.append({
                    "destination": website,
                    "enabled": True,
                    "schedule": {"start": "00:00", "end": "23:59"},
                    "restored_from_db": True
                })
        else:
            print("[STARTUP] Failed to apply: %s" % website)
    
    print("[STARTUP] ✅ Startup restoration complete! %d websites are blocked" % len(POLICIES))
    print("=" * 60)


class PolicyHandler(BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        print("[%s] %s" % (datetime.now().strftime('%H:%M:%S'), format % args))

    def _set_headers(self, code=200):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Connection", "close")
        self.end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Connection", "close")
        self.end_headers()

    def do_GET(self):
        try:
            print("[%s] GET request - returning %d policies" % (datetime.now().strftime('%H:%M:%S'), len(POLICIES)))
            self._set_headers(200)
            response = {
                "status": "ok",
                "policies": POLICIES,
                "count": len(POLICIES)
            }
            response_data = json.dumps(response).encode("utf-8")
            self.wfile.write(response_data)
            self.wfile.flush()
        except BrokenPipeError:
            print("[%s] Client disconnected before response completed (GET)" % datetime.now().strftime('%H:%M:%S'))
        except Exception as e:
            print("[ERROR] do_GET failed: %s" % str(e))
            try:
                self._set_headers(500)
                error_response = json.dumps({"status": "error", "message": str(e)}).encode("utf-8")
                self.wfile.write(error_response)
                self.wfile.flush()
            except:
                pass

    def do_POST(self):
        try:
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length).decode("utf-8")
            print("[%s] POST: %s" % (datetime.now().strftime('%H:%M:%S'), post_data))

            payload = json.loads(post_data)
            action = payload.get("action")
            domain = payload.get("domain") or payload.get("destination") or payload.get("website")

            if not action or not domain:
                self._set_headers(400)
                error_response = json.dumps({"status": "error", "message": "Missing action or domain"}).encode("utf-8")
                self.wfile.write(error_response)
                self.wfile.flush()
                return

            # Clean domain name
            domain = domain.replace('http://', '').replace('https://', '').replace('www.', '').strip('/')

            if action == "block":
                success, message = self.block_website(domain)
                if success:
                    # Check if policy already exists
                    existing = False
                    for p in POLICIES:
                        if p.get("destination") == domain:
                            p["enabled"] = True
                            p["schedule"] = payload.get("schedule", {"start": "00:00", "end": "23:59"})
                            existing = True
                            break

                    if not existing:
                        POLICIES.append({
                            "destination": domain,
                            "enabled": True,
                            "schedule": payload.get("schedule", {"start": "00:00", "end": "23:59"})
                        })

            elif action == "unblock":
                success, message = self.unblock_website(domain)
                if success:
                    POLICIES[:] = [p for p in POLICIES if p.get("destination") != domain]
            else:
                success = False
                message = "Unknown action: %s" % action

            self._set_headers(200 if success else 500)
            response = {
                "status": "ok" if success else "error",
                "message": message,
                "policies": POLICIES,
                "count": len(POLICIES)
            }
            response_data = json.dumps(response).encode("utf-8")
            self.wfile.write(response_data)
            self.wfile.flush()

        except BrokenPipeError:
            print("[%s] Client disconnected before response completed (POST)" % datetime.now().strftime('%H:%M:%S'))
        except json.JSONDecodeError as e:
            print("[ERROR] Invalid JSON: %s" % str(e))
            try:
                self._set_headers(400)
                error_response = json.dumps({"status": "error", "message": "Invalid JSON"}).encode("utf-8")
                self.wfile.write(error_response)
                self.wfile.flush()
            except:
                pass
        except Exception as e:
            print("[ERROR] do_POST failed: %s" % str(e))
            try:
                self._set_headers(500)
                error_response = json.dumps({"status": "error", "message": str(e)}).encode("utf-8")
                self.wfile.write(error_response)
                self.wfile.flush()
            except:
                pass

    def block_website(self, domain):
        try:
            # Method 1: Add to /etc/hosts (for Pi itself)
            with open('/etc/hosts', 'r') as f:
                content = f.read()
                if "127.0.0.1 %s" % domain in content or "127.0.0.1 www.%s" % domain in content:
                    print("[INFO] %s already in /etc/hosts" % domain)
                else:
                    with open('/etc/hosts', 'a') as f:
                        f.write("\n# SEER Policy %s\n" % datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
                        f.write("127.0.0.1 %s\n" % domain)
                        f.write("127.0.0.1 www.%s\n" % domain)

            # Method 2: Add to DNSMasq (for all network clients)
            dnsmasq_file = "/etc/dnsmasq.d/blocked-sites.conf"
            
            # Read current blocks
            blocked_domains = set()
            try:
                with open(dnsmasq_file, 'r') as f:
                    for line in f:
                        if line.startswith("address=/"):
                            blocked_domains.add(line.strip())
            except:
                pass
            
            # Add new blocks (including wildcard for all subdomains)
            new_entries = [
                "address=/%s/127.0.0.1" % domain,
                "address=/.%s/127.0.0.1" % domain  # Wildcard for all subdomains
            ]
            
            for entry in new_entries:
                blocked_domains.add(entry)
            
            # Write back to file
            with open(dnsmasq_file, 'w') as f:
                f.write("# SEER Temporal Policy - Blocked Domains\n")
                f.write("# This file is managed by temporal_policy.py\n")
                f.write("# Last updated: %s\n\n" % datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
                for entry in sorted(blocked_domains):
                    f.write(entry + "\n")
            
            # Restart DNSMasq to apply changes
            subprocess.run(['systemctl', 'restart', 'dnsmasq'],
                         check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            # ========== SAVE TO DATABASE ==========
            save_blocked_website_to_db(domain)

            print("[SUCCESS] Blocked: %s (via /etc/hosts and DNSMasq)" % domain)
            return True, "%s blocked successfully" % domain

        except PermissionError:
            return False, "Permission denied - run with sudo"
        except Exception as e:
            return False, "Error blocking %s: %s" % (domain, str(e))

    def unblock_website(self, domain):
        try:
            # Remove from /etc/hosts
            with open('/etc/hosts', 'r') as f:
                lines = f.readlines()

            new_lines = []
            skip_comment = False

            for line in lines:
                if domain in line and ("127.0.0.1" in line or "::1" in line):
                    continue
                if "SEER Policy" in line:
                    skip_comment = True
                    continue
                if skip_comment and not line.strip():
                    skip_comment = False
                    continue
                new_lines.append(line)

            with open('/etc/hosts', 'w') as f:
                f.writelines(new_lines)

            # Remove from DNSMasq
            dnsmasq_file = "/etc/dnsmasq.d/blocked-sites.conf"
            
            try:
                with open(dnsmasq_file, 'r') as f:
                    lines = f.readlines()
                
                with open(dnsmasq_file, 'w') as f:
                    f.write("# SEER Temporal Policy - Blocked Domains\n")
                    f.write("# This file is managed by temporal_policy.py\n")
                    f.write("# Last updated: %s\n\n" % datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
                    for line in lines:
                        # Skip lines containing the domain
                        if domain not in line or line.startswith("#"):
                            if not (line.startswith("#") and "managed by" in line):
                                if not (line.startswith("#") and "Last updated" in line):
                                    if line.strip() and not line.startswith("# SEER"):
                                        f.write(line)
            except:
                pass
            
            # Restart DNSMasq to apply changes
            subprocess.run(['systemctl', 'restart', 'dnsmasq'],
                         check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            # ========== REMOVE FROM DATABASE ==========
            remove_blocked_website_from_db(domain)

            print("[SUCCESS] Unblocked: %s (from /etc/hosts and DNSMasq)" % domain)
            return True, "%s unblocked successfully" % domain

        except PermissionError:
            return False, "Permission denied - run with sudo"
        except Exception as e:
            return False, "Error unblocking %s: %s" % (domain, str(e))


def run():
    print("=" * 60)
    print("Temporal Policy Backend - Port %d" % SERVER_PORT)
    print("=" * 60)

    # Initialize database on startup
    print("[STARTUP] Initializing database...")
    if not ensure_db_initialized():
        print("[WARNING] Database initialization had issues, continuing anyway...")

    # Automatically kill any process on the port
    print("[STARTUP] Checking port %d..." % SERVER_PORT)
    kill_process_on_port(SERVER_PORT)

    # Load blocked websites from database on startup
    load_and_apply_blocked_websites()

    try:
        server = HTTPServer((HOST_NAME, SERVER_PORT), PolicyHandler)
        print("[STARTUP] Successfully bound to port %d" % SERVER_PORT)
        print("=" * 60)
        print("Ready! Waiting for requests...")
        print("=" * 60)
        server.serve_forever()
    except OSError as e:
        if e.errno == 98:
            print("[ERROR] Port %d still in use" % SERVER_PORT)
            print("[ERROR] Try: sudo fuser -k %d/tcp" % SERVER_PORT)
        else:
            print("[ERROR] %s" % str(e))
    except KeyboardInterrupt:
        print("\n[SHUTDOWN] Server stopped")
        server.server_close()


if __name__ == "__main__":
    run()
