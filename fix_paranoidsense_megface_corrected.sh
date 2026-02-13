#!/usr/bin/env bash
set -e

if [ ! -d "packages/apps/ParanoidSense" ]; then
  echo "ERROR: Run from ROM root (~/PIXELOS16)"
  exit 1
fi

FILE="packages/apps/ParanoidSense/Android.bp"

echo "=== ParanoidSense libmegface fix (IMPROVED) ==="

# Backup
if [ ! -f "$FILE.bak" ]; then
  cp "$FILE" "$FILE.bak"
  echo "✓ Backup created"
fi

echo "1) Uncommenting libmegface in required[] list..."
# Make sure the dependency is active
sed -i -E 's/^([[:space:]]*)\/\/[[:space:]]*"libmegface",/\1"libmegface",/' "$FILE"

echo "2) Commenting the entire libmegface module block..."
# Use Python for reliable block commenting
python3 << 'PYTHON_SCRIPT'
import re

with open("packages/apps/ParanoidSense/Android.bp", "r") as f:
    lines = f.readlines()

output = []
in_libmegface_block = False
block_depth = 0
skip_block = False

for line in lines:
    # Check if this line starts a cc_ module
    if re.match(r'^\s*cc_\w+\s*\{', line) and not in_libmegface_block:
        in_libmegface_block = True
        block_depth = 1
        block_start = len(output)
        block_lines = [line]
        continue
    
    if in_libmegface_block:
        block_lines.append(line)
        
        # Count braces
        block_depth += line.count('{') - line.count('}')
        
        # Block ended
        if block_depth == 0:
            # Check if this block contains name: "libmegface"
            block_text = ''.join(block_lines)
            if re.search(r'name:\s*"libmegface"', block_text):
                # Comment out entire block
                for bline in block_lines:
                    if not bline.strip().startswith('//'):
                        output.append('// ' + bline)
                    else:
                        output.append(bline)
                skip_block = True
            else:
                # Keep block as-is
                output.extend(block_lines)
            
            in_libmegface_block = False
            block_lines = []
            continue
    
    if not in_libmegface_block:
        output.append(line)

with open("packages/apps/ParanoidSense/Android.bp", "w") as f:
    f.writelines(output)

print("✓ Module block commented")
PYTHON_SCRIPT

echo ""
echo "3) Verification:"
echo ""

# Show the required section
echo "Required dependencies:"
grep -A 10 'required:' "$FILE" | grep -E '(required:|libmegface)' || true

echo ""
echo "Libmegface module definition:"
grep -B 1 -A 3 'name: "libmegface"' "$FILE" | head -5 || true

echo ""
echo "✅ Done! Now run:"
echo "   rm -rf out/soong"
echo "   mka bacon"
