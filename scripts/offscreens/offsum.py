# Sums a CA_PRINT_OFFSCREENS log (offscreens.sh) per frame: which kinds of offscreen pass, how many per frame.
import re, sys, collections
for path in sys.argv[1:]:
    frames = collections.OrderedDict()
    for line in open(path, errors='replace'):
        m = re.search(r'CADebug\] \[(\d+)\]\[RENDER\] (.*)$', line)
        if not m: continue
        body = re.sub(r'\(0x[0-9a-f]+\) ', '', m.group(2)); body = re.sub(r', id:0x[0-9a-f]+', '', body)
        frames.setdefault(m.group(1), []).append(body)
    n = len(frames)
    kinds = collections.Counter()
    for f in frames.values():
        for b in f:
            k = re.search(r'offscreen-flags \[([^\]]*)\]', b)
            kinds[k.group(1) if k else ('framebuffer' if 'framebuffer' in b else 'plain (mask/group)')] += 1
    print(f'== {path}: {n} frames in ~3 s')
    for k, c in kinds.most_common(): print(f'   {k:28s} {c:6d} total  {c/max(n,1):6.1f} per frame')
