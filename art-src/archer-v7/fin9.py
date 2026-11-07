import json, os, glob, shutil, sys
from PIL import Image
Image.MAX_IMAGE_PIXELS=None
SC='/tmp/claude-0/-home-claude-Anchors/ef01fd61-7b0a-5f75-8c17-bcaa51a14f40/scratchpad'
GS='/mnt/project-files/art/game-staging/archer'
AN='/mnt/project-files/art/claude-sprites/archer-stages-anim-16dir'
fc={'walk':{'L':6,'R':18},'combat_walk':{'L':6,'R':18},'run':{'L':4,'R':12},'combat_run':{'L':4,'R':12}}
man=json.load(open(f'{GS}/manifest.json'))
s=open(f'{SC}/apv/data.js').read(); D=json.loads(s[s.index('{'):s.rstrip().rstrip(';').rindex('}')+1])
commit=[]; pfiles={}
for n in range(1,6):
    k=f'xstage{n}'; p=f'{SC}/astganim9/{k}/{k}_16dir_sheet.json'
    if not os.path.exists(p): print('skip',k); continue
    d=json.load(open(p)); im=Image.open(f'{SC}/astganim9/{k}/{k}_16dir_sheet.png'); fw,fh=d['frameSize']
    gd=f'{GS}/a{n}_crossbow'; os.makedirs(gd,exist_ok=True)
    for f in glob.glob(f'{gd}/*.png'): os.remove(f)
    for f in glob.glob(f'{SC}/apv/s/{k}_*.webp'): os.remove(f)
    for a,nf in d['frames'].items():
        o=Image.new('RGBA',(fw*nf,fh*16),(0,0,0,0))
        for r,dd in enumerate(d['directions']):
            ri=d['rows'].index(a+'_'+dd); o.paste(im.crop((0,ri*fh,fw*nf,ri*fh+fh)),(0,r*fh))
        o.save(f'{gd}/{a}.png'); o.save(f'{SC}/apv/s/{k}_{a}.webp',lossless=True,method=4)
        commit.append({'devicePath':f'C:\\Users\\easte\\OneDrive\\MAZ\\Godot\\MAJ\\Art\\ConceptRuntime\\characters\\archer\\a{n}_crossbow\\{a}.png','stagedPath':f'{gd}/{a}.png'})
        pfiles[f's/{k}_{a}.webp']=f's/{k}_{a}.webp'
    man['sets'][f'a{n}_crossbow']={'stage':n,'bow':'crossbow','frames':d['frames'],'hitFrames':d['hitFrames'],
        'attackPool':[x['anim'] for x in d['attackPool']],'footContactFrames':{a:v for a,v in fc.items() if a in d['frames']},'shadow':'shadows/shadow_human.png'}
    st=[x for x in D['sets'] if x['id']==k][0]
    for x in ('frames','hitFrames','attackPool','moveForwardFrames'): st[x]=d[x]
    # replace anim folder copy
    dst=f'{AN}/{k}'
    if os.path.isdir(dst): shutil.rmtree(dst)
    shutil.copytree(f'{SC}/astganim9/{k}',dst)
    print('done',k,list(d['frames']))
json.dump(man,open(f'{GS}/manifest.json','w'),indent=1,ensure_ascii=False)
open(f'{SC}/apv/data.js','w').write('const DATA='+json.dumps(D,ensure_ascii=False)+';\n')
commit.append({'devicePath':'C:\\Users\\easte\\OneDrive\\MAZ\\Godot\\MAJ\\Art\\ConceptRuntime\\characters\\archer\\manifest.json','stagedPath':f'{GS}/manifest.json'})
json.dump(commit[:50],open('/mnt/project-files/art/game-staging/batch5.json','w')); json.dump(commit[50:],open('/mnt/project-files/art/game-staging/batch6.json','w'))
pfiles.update({'data.js':'data.js','index.html':'index.html'}); json.dump(pfiles,open(f'{SC}/apv/files9.json','w'))
print(len(commit), len(pfiles))
