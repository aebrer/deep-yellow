# Web Deployment Configuration

This directory contains web server configuration templates for deploying Backrooms Power Crawl.

## Files

- **`.htaccess`** - Apache configuration
- **`nginx.conf`** - Nginx configuration snippet
- **`deploy.sh`** - Deployment script (TODO)

## Quick Start

### Apache Deployment

1. Export game from Godot Editor (Windows)
2. Copy `.htaccess` to `build/web/.htaccess`
3. Upload `build/web/*` to your web server
4. Verify headers are set:
   ```bash
   curl -I https://yoursite.com/backrooms/
   ```

### Nginx Deployment

1. Export game from Godot Editor (Windows)
2. Add `nginx.conf` location block to your server config
3. Reload nginx:
   ```bash
   sudo nginx -t
   sudo systemctl reload nginx
   ```
4. Upload `build/web/*` to configured path

## Critical Requirements

**These headers MUST be present or the game will not work:**

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

These enable SharedArrayBuffer, which Godot's threading requires.

## Testing Deployment

```bash
# Check headers
curl -I https://yoursite.com/backrooms/

# Should see:
# cross-origin-opener-policy: same-origin
# cross-origin-embedder-policy: require-corp

# If missing, threading will fail and chunks won't generate
```

## Browser Console Errors

**If headers are missing:**
```
ReferenceError: SharedArrayBuffer is not defined
```

**If threading fails:**
```
[ChunkManager] Chunk generation timed out
Worker thread failed to start
```

## See Also

- [docs/WEB_EXPORT.md](../docs/WEB_EXPORT.md) - Full export guide
- [scripts/serve_web.py](../scripts/serve_web.py) - Local testing server
