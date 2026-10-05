#!/usr/bin/env python3
"""Lightweight TD6.2.1 project-file audit.

TD .al files are XML-like but use attribute values such as "UsedInP&R", so
standard XML parsers reject them.  This checker intentionally uses text/regex.
It verifies the failure modes seen in this repository:
  1) duplicate <File Path="..."> entries after branch merges;
  2) non-CRLF .al files on Windows checkout/package paths;
  3) required shared RTL accidentally marked AutoExcluded from synthesis.
"""
from pathlib import Path
from collections import Counter
import re, sys

files = [Path(x) for x in sys.argv[1:]] or [
    Path('FPGA_Competition_HDMI_MASTER.al'),
    Path('FPGA_Competition_HDMI_SLAVE.al'),
]
failed = False
for p in files:
    b = p.read_bytes()
    text = b.decode('utf-8-sig')
    paths = re.findall(r'<File Path="([^"]+)"', text)
    dup = [(k,v) for k,v in Counter(paths).items() if v > 1]
    crlf_ok = b'\r\n' in b and b.replace(b'\r\n', b'').find(b'\n') == -1
    print(f'{p}: file_entries={len(paths)} CRLF={"OK" if crlf_ok else "BAD"}')
    if dup:
        failed = True
        print('  DUPLICATE FILE ENTRIES:')
        for k,v in dup:
            print(f'    {v}x {k}')
    if not crlf_ok:
        failed = True
        print('  WARNING: .al is not pure CRLF')
    if p.name == 'FPGA_Competition_HDMI_MASTER.al':
        fifo_block = re.search(
            r'<File Path="src/framebuf/async_fifo\.v">(.*?)</File>',
            text, re.S)
        if not fifo_block or not re.search(
                r'<Attr Name="UsedInSyn" Val="true"', fifo_block.group(1)):
            failed = True
            print('  REQUIRED SOURCE NOT ACTIVE: src/framebuf/async_fifo.v')
if failed:
    raise SystemExit(1)
print('PASS: TD project files have unique source paths and CRLF line endings.')
