import re,sys,glob
bad_syntax=[(r'//','integer division (5.3+)'),(r'\bgoto\b','goto (5.2+)'),(r'::','label (5.2+)'),(r'(?<![~=<>])&','bitwise and'),
            (r'<<|>>','bit shift'),(r'(?<![~=<>])~(?!=)','bitwise not/xor'),(r'\|','bitwise or')]
bad_api=[r'table\.unpack',r'table\.pack',r'\butf8\.',r'math\.type',r'\bload\s*\(',r'string\.pack',r'\brawlen\b',r'table\.move',
         r'C_Timer',r'\bMixin\b',r':SetShown\(',r':SetSize\(',r'SetColorTexture',r'SetAtlas',r'CreateMaskTexture',r'SetClipsChildren',
         r'SetIgnoreParentScale',r'C_EditMode',r'\bWrapTextInColorCode\b',r'GetMouseFoci',r'SetPropagateKeyboardInput',r'SetObeyStepOnDrag',
         r'NineSliceUtil',r'BackdropTemplate',r'\bIsTruthy\b',r'SetTexelSnappingBias',r'SetSnapToPixelGrid',r'C_AddOns']
def strip(src):
    out=[];i=0;n=len(src)
    while i<n:
        c=src[i]
        if src.startswith('--[[',i) or src.startswith('--[=[',i):
            j=src.find(']]',i); i=j+2 if j>=0 else n; continue
        if src.startswith('--',i):
            j=src.find('\n',i); i=j if j>=0 else n; continue
        if src.startswith('[[',i):
            j=src.find(']]',i); out.append('""'); i=j+2; continue
        if c in '"\'':
            j=i+1
            while j<n and src[j]!=c:
                if src[j]=='\\': 
                    if src[j+1] in 'zu': print("5.2+ escape \\"+src[j+1])
                    j+=1
                j+=1
            out.append('""'); i=j+1; continue
        out.append(c); i+=1
    return ''.join(out)
problems=0
for f in sorted(glob.glob(sys.argv[1]+'/*.lua')):
    raw=open(f).read(); code=strip(raw)
    for ln,line in enumerate(code.split('\n'),1):
        for pat,why in bad_syntax:
            if re.search(pat,line): print(f"{f}:{ln}: {why}: {line.strip()[:90]}"); problems+=1
    for ln,line in enumerate(raw.split('\n'),1):
        s=line.split('--')[0]
        for pat in bad_api:
            if re.search(pat,s): print(f"{f}:{ln}: retail/5.2+ API {pat}: {line.strip()[:90]}"); problems+=1
print("lint problems:",problems)
