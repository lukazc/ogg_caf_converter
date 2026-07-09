import struct, sys

def parse_caf(path, label):
    with open(path, 'rb') as f:
        b = f.read()
    print(f'=== {label} ({len(b)} bytes) ===')
    print(f'  File: {b[0:4]} ver={struct.unpack(">H", b[4:6])[0]} flags={struct.unpack(">H", b[6:8])[0]}')
    offset = 8
    while offset + 12 <= len(b):
        tag = b[offset:offset+4].decode('ascii', errors='replace')
        size = struct.unpack('>q', b[offset+4:offset+12])[0]
        end = offset + 12 + size
        print(f'  offset={offset:6d} tag={tag:5s} size={size:8d} (end={end})')
        if tag == 'kuki':
            print(f'    kuki raw ({size}B): {b[offset+12:offset+12+size].hex()}')
        if tag == 'pakt':
            np = struct.unpack('>q', b[offset+12:offset+20])[0]
            nvf = struct.unpack('>q', b[offset+20:offset+28])[0]
            pf = struct.unpack('>I', b[offset+28:offset+32])[0]
            rf = struct.unpack('>I', b[offset+32:offset+36])[0]
            print(f'    packets={np} validFrames={nvf} primingFrames={pf} remainderFrames={rf}')
        if tag == 'desc':
            sr = struct.unpack('>d', b[offset+12:offset+20])[0]
            fmt = b[offset+20:offset+24].decode('ascii')
            fpp = struct.unpack('>I', b[offset+32:offset+36])[0]
            ch = struct.unpack('>I', b[offset+36:offset+40])[0]
            print(f'    sr={sr} fmt={fmt} fpp={fpp} ch={ch}')
        if tag == 'data':
            ec = struct.unpack('>I', b[offset+12:offset+16])[0]
            print(f'    editCount={ec}')
        offset = end
    print()

parse_caf('test_resources/Thursday_at_19_08.caf', 'NATIVE iOS (works)')
parse_caf('test_resources/Tuesday_at_11_24_Tammany.opus', 'CONVERTED (fails)')
