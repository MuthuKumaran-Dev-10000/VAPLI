"""Fix script: removes the orphaned old HTML block left in server.py after ADMIN_DASHBOARD_HTML was refactored"""
import re

with open('server.py', 'r', encoding='utf-8') as f:
    content = f.read()

# The orphaned HTML is between the new _load_admin_html function and the FeedbackHTTPRequestHandler class.
# Strategy: find the end of the good _load_admin_html function, then find where the REAL
# FeedbackHTTPRequestHandler class body starts (def log_message), and remove all garbage in between.

# Marker 1: end of the valid _load_admin_html fallback return statement
MARKER_START = 'return "<html><body><h1>VAPLI Control Center</h1><p>admin.html not found in Server directory.</p></body></html>"'

# Marker 2: beginning of the real class method
MARKER_END = '    def log_message(self, format, *args):'

idx_start = content.find(MARKER_START)
idx_end = content.find(MARKER_END)

if idx_start == -1:
    print("ERROR: MARKER_START not found")
    exit(1)
if idx_end == -1:
    print("ERROR: MARKER_END not found")
    exit(1)

print(f"Start marker at: {idx_start}")
print(f"End marker at: {idx_end}")

# Extract everything between end of MARKER_START line and beginning of MARKER_END
between_start = idx_start + len(MARKER_START)
between_end = idx_end

print(f"Removing chars {between_start} to {between_end}")
print(f"Sample removed: {repr(content[between_start:between_start+200])}")

# Build replacement: keep function end, then blank lines, then class definition header, then log_message
replacement = '\n\n\nclass FeedbackHTTPRequestHandler(BaseHTTPRequestHandler):\n    """Zero-dependency HTTP Request Handler to serve feedback forms and provide a server control panel"""\n\n'

new_content = content[:between_start] + replacement + content[idx_end:]

with open('server.py', 'w', encoding='utf-8') as f:
    f.write(new_content)

print(f"Done! File size: {len(new_content)} bytes (was {len(content)} bytes)")
