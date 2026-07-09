import struct
def p(path):
    with open(path,'rb') as f: b=f.read()
    off=8; tags=[]
    while off+12<=len(b):
        tag=b[off:off+4].decode()
        sz=struct.unpack('>q',b[off+4:off+12])[0]
        end=off+12+sz
        detail=''
        if tag=='pakt':
            pf=struct.unpack('>I',b[off+28:off+32])[0]
            detail=f'primingFrames={pf}'
        if tag=='data':
            ec=struct.unpack('>I',b[off+12:off+16])[0]
            detail=f'editCount={ec}'
        tags.append(f'{tag}')
        off=end
    print(f'{"→".join(tags)}  {" ".join([detail]) if detail else ""}')
print('Native iOS:', end=' '); p('test_resources/Thursday_at_19_08.caf')
print('Our output:', end=' '); p('_verify.caf')
