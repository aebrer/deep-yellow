#!/usr/bin/env python3
"""
Local web server for testing Godot HTML5 exports with threading support.

This server adds the required Cross-Origin headers for SharedArrayBuffer,
which is needed for Godot's threading to work in browsers.

Usage:
    python3 scripts/serve_web.py

Then open http://localhost:8000 in your browser.
"""

from http.server import HTTPServer, SimpleHTTPRequestHandler
import os
import sys

class ThreadSupportHTTPRequestHandler(SimpleHTTPRequestHandler):
    """HTTP handler that adds headers required for SharedArrayBuffer/threading"""

    def end_headers(self):
        # Required headers for SharedArrayBuffer (Godot threading)
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')

        # Optional: Cache control for development
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')

        super().end_headers()

    def log_message(self, format, *args):
        """Override to add colored output"""
        print(f"[{self.log_date_time_string()}] {format % args}")

def main():
    PORT = 8000
    BUILD_DIR = 'build/web'

    # Verify build directory exists
    if not os.path.exists(BUILD_DIR):
        print(f"ERROR: Build directory '{BUILD_DIR}' not found!")
        print()
        print("You need to export the game first:")
        print("  1. Open project in Godot Editor (Windows)")
        print("  2. Project → Export → Web → Export Project")
        print("  3. Verify files appear in build/web/")
        print()
        print(f"Expected files in {BUILD_DIR}:")
        print("  - index.html")
        print("  - index.js")
        print("  - index.wasm")
        print("  - index.pck")
        sys.exit(1)

    # Check for required files
    required_files = ['index.html', 'index.js', 'index.wasm', 'index.pck']
    missing = [f for f in required_files if not os.path.exists(os.path.join(BUILD_DIR, f))]

    if missing:
        print(f"WARNING: Missing files in {BUILD_DIR}:")
        for f in missing:
            print(f"  - {f}")
        print()
        print("Export may be incomplete. Continue anyway? (y/n) ", end='')
        if input().lower() != 'y':
            sys.exit(1)

    # Change to build directory
    os.chdir(BUILD_DIR)

    # Start server
    server = HTTPServer(('localhost', PORT), ThreadSupportHTTPRequestHandler)

    print()
    print("=" * 70)
    print("DEEP YELLOW - Web Export Server")
    print("=" * 70)
    print()
    print(f"Server running at: http://localhost:{PORT}")
    print()
    print("Required headers enabled:")
    print("  ✓ Cross-Origin-Opener-Policy: same-origin")
    print("  ✓ Cross-Origin-Embedder-Policy: require-corp")
    print()
    print("These headers enable SharedArrayBuffer for threading support.")
    print("Without them, chunk generation will fail!")
    print()
    print("Press Ctrl+C to stop server")
    print("=" * 70)
    print()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print()
        print("Server stopped.")
        sys.exit(0)

if __name__ == '__main__':
    main()
