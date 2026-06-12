#!/usr/bin/env python3
"""Rapid error traffic generator for SLO alert testing."""
import urllib.request
import threading
import time
import sys

TARGET = "http://localhost:8888/api/bug"
WORKERS = int(sys.argv[1]) if len(sys.argv) > 1 else 4
STOP_FLAG = threading.Event()

def worker(wid):
    count = 0
    while not STOP_FLAG.is_set():
        try:
            req = urllib.request.urlopen(TARGET, timeout=1)
            req.close()
        except:
            pass
        count += 1
        if count % 200 == 0:
            print(f"[Worker-{wid}] Sent: {count}", flush=True)
    print(f"[Worker-{wid}] Total: {count}", flush=True)

threads = []
print(f"Starting {WORKERS} workers targeting {TARGET}")
for i in range(WORKERS):
    t = threading.Thread(target=worker, args=(i+1,))
    t.start()
    threads.append(t)
    print(f"[+] Worker {i+1} started")

print("Traffic is flowing. Press Ctrl+C to stop.")
try:
    while True:
        time.sleep(10)
        print(f"[{time.strftime('%H:%M:%S')}] Still sending errors...", flush=True)
except KeyboardInterrupt:
    print("Stopping...")
    STOP_FLAG.set()
    for t in threads:
        t.join()
    print("Done.")
