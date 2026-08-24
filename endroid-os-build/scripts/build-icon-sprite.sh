#!/bin/bash
# build-icon-sprite.sh - Generate offline SVG sprite from referenced Lucide icons
# This script extracts all icon names from the UI source files and builds a single SVG sprite

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_DIR="$(dirname "$SCRIPT_DIR")/ui"
OUTPUT_FILE="$UI_DIR/icons.svg"
LUCIDE_JS="$UI_DIR/lucide.js"

echo "=== Building Icon Sprite ==="

# Check if lucide.js exists
if [ ! -f "$LUCIDE_JS" ]; then
    echo "ERROR: lucide.js not found at $LUCIDE_JS"
    echo "Download it from https://unpkg.com/lucide@latest/dist/umd/lucide.js"
    exit 1
fi

# Use Python to do the heavy lifting - more reliable parsing
python3 << 'PYEOF'
import re
import sys

UI_DIR = "/workspace/endroid-os-build/ui"
LUCIDE_JS = f"{UI_DIR}/lucide.js"
OUTPUT_FILE = f"{UI_DIR}/icons.svg"

# Read lucide.js
with open(LUCIDE_JS, 'r') as f:
    content = f.read()

# Extract icon names from index.html (data-lucide="...")
with open(f"{UI_DIR}/index.html", 'r') as f:
    html_content = f.read()
html_icons = set(re.findall(r'data-lucide="([^"]+)"', html_content))

# Extract icon names from apps.js (icon:"...")
with open(f"{UI_DIR}/apps.js", 'r') as f:
    apps_content = f.read()
apps_icons = set(re.findall(r'icon:"([^"]+)"', apps_content))

# Combine and filter out template literals (${...})
all_icons = (html_icons | apps_icons) - {x for x in (html_icons | apps_icons) if '${' in x}
all_icons = sorted(all_icons)

print(f"Found {len(all_icons)} unique icon names")
print("")

# Parse all icon definitions from lucide.js
icon_defs = {}
# Match both single-line and multi-line icon definitions
pattern = r'const\s+(\w+)\s*=\s*\[(.*?)\];'
for match in re.finditer(pattern, content, re.DOTALL):
    name = match.group(1)
    body = match.group(2)
    icon_defs[name] = body

def kebab_to_pascal(name):
    """Convert kebab-case to PascalCase with special handling for aliases"""
    # Handle Lucide icon name aliases
    aliases = {
        'check-circle': 'CircleCheckBig',
        'home': 'House',
    }
    if name in aliases:
        return aliases[name]
    return ''.join(word.capitalize() for word in name.split('-'))

def extract_svg_elements(icon_body):
    """Extract SVG elements from icon definition"""
    elements = []
    
    for line in icon_body.split('\n'):
        # Path: ["path", { d: "..." }]
        m = re.search(r'\["path",\s*\{\s*d:\s*"([^"]+)"', line)
        if m:
            elements.append(f'<path d="{m.group(1)}"/>')
            continue
        
        # Circle: ["circle", { cx: "...", cy: "...", r: "..." }]
        m = re.search(r'\["circle",\s*\{\s*cx:\s*"([^"]+)".*?cy:\s*"([^"]+)".*?r:\s*"([^"]+)"', line)
        if m:
            elements.append(f'<circle cx="{m.group(1)}" cy="{m.group(2)}" r="{m.group(3)}"/>')
            continue
        
        # Rect: ["rect", { x: "...", y: "...", width: "...", height: "..." }]
        m = re.search(r'\["rect",\s*\{\s*x:\s*"([^"]+)".*?y:\s*"([^"]+)".*?width:\s*"([^"]+)".*?height:\s*"([^"]+)"', line)
        if m:
            elements.append(f'<rect x="{m.group(1)}" y="{m.group(2)}" width="{m.group(3)}" height="{m.group(4)}"/>')
            continue
        
        # Line: ["line", { x1: "...", y1: "...", x2: "...", y2: "..." }]
        m = re.search(r'\["line",\s*\{\s*x1:\s*"([^"]+)".*?y1:\s*"([^"]+)".*?x2:\s*"([^"]+)".*?y2:\s*"([^"]+)"', line)
        if m:
            elements.append(f'<line x1="{m.group(1)}" y1="{m.group(2)}" x2="{m.group(3)}" y2="{m.group(4)}"/>')
            continue
        
        # Polyline: ["polyline", { points: "..." }]
        m = re.search(r'\["polyline",\s*\{\s*points:\s*"([^"]+)"', line)
        if m:
            elements.append(f'<polyline points="{m.group(1)}"/>')
            continue
        
        # Polygon: ["polygon", { points: "..." }]
        m = re.search(r'\["polygon",\s*\{\s*points:\s*"([^"]+)"', line)
        if m:
            elements.append(f'<polygon points="{m.group(1)}"/>')
            continue
    
    return elements

# Build the sprite
missing_icons = []
processed_count = 0

with open(OUTPUT_FILE, 'w') as out:
    out.write('<svg xmlns="http://www.w3.org/2000/svg" style="display:none;">\n')
    
    for icon_name in all_icons:
        pascal_name = kebab_to_pascal(icon_name)
        
        if pascal_name not in icon_defs:
            missing_icons.append(icon_name)
            continue
        
        elements = extract_svg_elements(icon_defs[pascal_name])
        
        if elements:
            out.write(f'  <symbol id="{icon_name}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">\n')
            for elem in elements:
                out.write(f'{elem}\n')
            out.write('  </symbol>\n')
            print(f"  ✓ {icon_name}")
            processed_count += 1
        else:
            missing_icons.append(icon_name)
    
    out.write('</svg>\n')

print("")
print(f"Sprite written to: {OUTPUT_FILE}")

if missing_icons:
    print("")
    print("ERROR: Missing icon definitions:")
    for icon in missing_icons:
        print(f"  ✗ {icon}")
    print("")
    print("These icons are referenced in the UI but not found in lucide.js")
    print("Either: 1) Download updated lucide.js, 2) Remove references from UI, or 3) Add custom icons")
    sys.exit(1)

print(f"Successfully generated sprite with {processed_count} icons")
print("=== Icon Sprite Build Complete ===")
PYEOF
