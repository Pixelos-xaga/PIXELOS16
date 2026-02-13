#!/usr/bin/env bash
set -e

# Detect ROM root (current directory if it contains packages/apps)
if [ -d "packages/apps/ParanoidSense" ]; then
  ROOT="$(pwd)"
elif [ -d "PIXELOS16/packages/apps/ParanoidSense" ]; then
  ROOT="$(pwd)/PIXELOS16"
else
  echo "ERROR: Run this script from your ROM root directory"
  echo "Expected to find: packages/apps/ParanoidSense"
  exit 1
fi

FILE="$ROOT/packages/apps/ParanoidSense/Android.bp"

echo "== ParanoidSense libmegface fix (CORRECTED) =="
echo "ROM root: $ROOT"

if [ ! -f "$FILE" ]; then
  echo "ERROR: $FILE not found."
  exit 1
fi

# Backup once
if [ ! -f "$FILE.bak" ]; then
  cp "$FILE" "$FILE.bak"
  echo "Backup created: $FILE.bak"
else
  echo "Using existing backup: $FILE.bak"
fi

echo ""
echo "1) KEEPING libmegface in required[] list (so it uses MTK's version)..."
# Ensure libmegface dependency is UNCOMMENTED
sed -i -E 's/^([[:space:]]*)\/\/[[:space:]]*"libmegface",/\1"libmegface",/' "$FILE"

echo "2) Commenting ONLY the libmegface module definition block..."
# Comment the whole cc_* block that contains name: "libmegface"
awk '
  BEGIN { inblock=0 }
  {
    if ($0 ~ /^[[:space:]]*cc_.*\{/ && !inblock) {
      # Potential start of a module; buffer until we know if it contains libmegface
      inblock=1; buf[0]=$0; n=1; next
    }
    if (inblock) {
      buf[n++]=$0
      if ($0 ~ /^[[:space:]]*\}/) {
        # End of block; check if it contains the target name
        has=0
        for (i=0;i<n;i++) {
          if (buf[i] ~ /name:[[:space:]]*"libmegface"/) { has=1; break }
        }
        # Print commented or original
        for (i=0;i<n;i++) {
          if (has && buf[i] !~ /^[[:space:]]*\/\//) {
            print "// " buf[i]
          } else {
            print buf[i]
          }
        }
        inblock=0; n=0
      }
      next
    }
    print $0
  }
' "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"

echo ""
echo "3) Verifying..."
echo ""
echo "Checking module definition is commented:"
if grep -A 5 'name:[[:space:]]*"libmegface"' "$FILE" 2>/dev/null | head -1 | grep '^[[:space:]]*\/\/' >/dev/null; then
  echo "  ✓ libmegface module definition is commented"
else
  echo "  ✗ WARNING: libmegface module definition might not be commented"
fi

echo ""
echo "Checking dependency is NOT commented:"
if grep 'required:[[:space:]]*\[' -A 20 "$FILE" 2>/dev/null | grep '"libmegface"' | grep -v '^[[:space:]]*\/\/' >/dev/null; then
  echo "  ✓ libmegface is in required dependencies (will use MTK's version)"
else
  echo "  ✗ WARNING: libmegface might be commented in required list"
fi

echo ""
echo "✅ Done!"
echo ""
echo "Next steps:"
echo "  rm -rf out/soong"
echo "  mka bacon"
