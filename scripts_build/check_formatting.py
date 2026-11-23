import sys
import glob

files = sys.argv[1:] if len(sys.argv) > 1 else sorted(glob.glob('capitulos/*.md'))

total_errors = 0
for fpath in files:
    with open(fpath, 'r', encoding='utf-8') as f:
        lines = f.readlines()
        
    words = len("".join(lines).split())
    in_code = False
    over_72 = []
    
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith('```'):
            in_code = not in_code
            continue
        if in_code:
            line_content = line.rstrip('\r\n')
            if len(line_content) > 72:
                over_72.append((i, len(line_content), line_content))
                
    print(f"[{fpath}] Palavras: {words} | Linhas de codigo > 72 chars: {len(over_72)}")
    if over_72:
        total_errors += len(over_72)
        for ln, sz, txt in over_72:
            print(f"   L{ln} ({sz}): {txt}")

sys.exit(total_errors)
