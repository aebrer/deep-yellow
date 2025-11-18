# Web Export Guide

This document covers exporting Backrooms Power Crawl for web deployment.

## Export Configuration

The project is configured to export to `build/web/` with the following critical settings:

### Thread Support (REQUIRED)

**The game REQUIRES thread support to function!**
- ChunkGenerationThread uses a worker thread for procedural generation
- Without threads, chunks will never generate and the game will hang

Export preset settings:
```
variant/thread_support = true
threads/emscripten_pool_size = 8
threads/godot_pool_size = 4
```

## Exporting from Godot Editor

1. Open the project in Godot Editor (Windows)
2. Go to **Project → Export**
3. Select the "Web" preset
4. Click **Export Project**
5. Verify output is in `build/web/`

## Web Server Requirements

### SharedArrayBuffer and Threading

Godot's threading requires **SharedArrayBuffer**, which has strict browser security requirements:

**Your web server MUST send these HTTP headers:**
```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

Without these headers, the game will fail to start in modern browsers.

### Example: Apache .htaccess

```apache
# In build/web/.htaccess or server config:
<IfModule mod_headers.c>
    Header set Cross-Origin-Opener-Policy "same-origin"
    Header set Cross-Origin-Embedder-Policy "require-corp"
</IfModule>
```

### Example: Nginx

```nginx
location /backrooms/ {
    add_header Cross-Origin-Opener-Policy "same-origin";
    add_header Cross-Origin-Embedder-Policy "require-corp";
}
```

### Example: Python HTTP Server (Testing)

```python
#!/usr/bin/env python3
from http.server import HTTPServer, SimpleHTTPRequestHandler
import os

class CORSRequestHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        super().end_headers()

if __name__ == '__main__':
    os.chdir('build/web')
    server = HTTPServer(('localhost', 8000), CORSRequestHandler)
    print('Serving at http://localhost:8000')
    server.serve_forever()
```

## Testing Locally

1. Export the project from Godot Editor
2. Run the Python server script above from project root
3. Open http://localhost:8000 in your browser
4. Verify chunks generate properly (look for movement working)

## Deployment Checklist

- [ ] Export from Godot with "Web" preset
- [ ] Verify `build/web/` contains:
  - `index.html`
  - `index.js`
  - `index.wasm`
  - `index.pck`
  - `index.icon.png`
- [ ] Configure web server headers (COOP/COEP)
- [ ] Upload `build/web/*` to hosting
- [ ] Test in browser (check console for threading errors)
- [ ] Verify gameplay works (move around, chunks generate)

## Known Issues

### Browser Compatibility

**Threading requires modern browsers:**
- Chrome/Edge 92+ (2021)
- Firefox 79+ (2020)
- Safari 15.2+ (2021)

Older browsers will fail to start with SharedArrayBuffer errors.

### Performance

Web builds are slower than native:
- Chunk generation takes ~50-100ms (vs 10-20ms native)
- Still playable, just slightly more jitter on movement
- Consider reducing `MAX_LOADED_CHUNKS` in ChunkManager for web

### Controller Support

Gamepad API works in browsers, but:
- Requires user interaction before detecting controller
- Some button mappings may differ by browser
- Test thoroughly with Xbox/PlayStation controllers

## Troubleshooting

**"SharedArrayBuffer is not defined"**
→ Web server not sending COOP/COEP headers. Check server config.

**Chunks never load / game hangs after moving**
→ Worker thread failed to start. Check browser console for thread errors.

**"Failed to load .pck file"**
→ CORS issue or missing files. Ensure all files uploaded and server allows CORS.

**Performance very slow**
→ Expected on web. Try reducing max chunks or disabling some visual effects.

## Deployment Workflow

```bash
# 1. Export from Godot Editor (you must do this in Windows)
# 2. Verify build exists
ls build/web/

# 3. Test locally
python3 scripts/serve_web.py

# 4. Deploy to web server
rsync -avz build/web/ user@yourserver.com:/var/www/backrooms/

# 5. Verify headers are set
curl -I https://yoursite.com/backrooms/

# Should see:
# Cross-Origin-Opener-Policy: same-origin
# Cross-Origin-Embedder-Policy: require-corp
```

## Alpha Testing Recommendations

For alpha testers:

1. **Include browser requirements** in test instructions
2. **Provide fallback link** to native builds if web doesn't work
3. **Collect browser/OS info** from testers (compatibility data)
4. **Warn about performance** (web is slower than native)
5. **Test controller support** before announcing gamepad compatibility

## Resources

- [Godot Web Export Docs](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)
- [SharedArrayBuffer Requirements (MDN)](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/SharedArrayBuffer)
- [Cross-Origin Isolation Guide](https://web.dev/cross-origin-isolation-guide/)
