#!/bin/bash
# Export all .drawio diagrams to SVG using draw.io CLI
# Usage: npm run diagrams:export [specific-file.drawio]
#
# Requires: draw.io desktop app installed at /Applications/draw.io.app
# Source:   diagrams/*.drawio (project root)
# Output:   public/diagrams/*.svg (served as static assets)

DRAWIO="/Applications/draw.io.app/Contents/MacOS/draw.io"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$PROJECT_ROOT/diagrams"
OUT_DIR="$PROJECT_ROOT/public/diagrams"

if [ ! -f "$DRAWIO" ]; then
  echo "Error: draw.io not found at $DRAWIO"
  echo "Install from https://github.com/jgraph/drawio-desktop/releases"
  exit 1
fi

mkdir -p "$OUT_DIR"

export_file() {
  local src="$1"
  local basename=$(basename "$src" .drawio)
  local out="$OUT_DIR/${basename}.svg"

  echo "Exporting: $basename.drawio → $basename.svg"
  "$DRAWIO" --export --format svg --embed-svg-images --output "$out" "$src" 2>/dev/null

  if [ $? -eq 0 ] && [ -f "$out" ]; then
    echo "  ✓ $out"
  else
    echo "  ✗ Failed to export $basename"
    return 1
  fi
}

if [ -n "$1" ]; then
  if [ -f "$SRC_DIR/$1" ]; then
    export_file "$SRC_DIR/$1"
  elif [ -f "$1" ]; then
    export_file "$1"
  else
    echo "File not found: $1"
    exit 1
  fi
else
  echo "Exporting all diagrams..."
  echo "========================="
  count=0
  for f in "$SRC_DIR"/*.drawio; do
    [ -f "$f" ] || continue
    export_file "$f"
    count=$((count + 1))
  done
  echo "========================="
  echo "Done. Exported $count diagrams to $OUT_DIR/"
fi
