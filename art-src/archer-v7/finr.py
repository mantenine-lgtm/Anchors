import json, os, glob, shutil
from PIL import Image
Image.MAX_IMAGE_PIXELS=None
SC='/tmp/claude-0/-home-claude-Anchors/ef01fd61-7b0a-5f75-8c17-bcaa51a14f40/scratchpad'
GS='/mnt/project-files/art/game-staging/archer'; AN='/mnt/project-files/art/claude-sprites/archer-stages-anim-16dir'
man=json.load(open(f'{GS}/manifest.json'))
s=open(f'{SC}/apv/data.js').read(); D=json.loads(s[s.index('{'):s.rstrip().rstrip(';').rindex('}')+1])
commit=[]; pfiles={'data.js':'data.js','index.html':'index.html'}; done=[]
for p in sorted(glob.glob(f'{SC}/astgreact/*/*_16dir_react_sheet.json')):
    k=os.path.basename(p).split('_16dir')[0]; d=json.load(open(p)); im=Image.open(p.replace('.json','.png')); fw,fh=d['frameSize']
    gk=f"a{k[6:]}_crossbow" if k.startswith('xstage') else k; gd=f'{GS}/{gk}'; os.makedirs(gd,exist_ok=True)
    for a,nf in d['frames'].items():
        o=Image.new('RGBA',(fw*nf,fh*16),(0,0,0,0))
        for r,dd in enumerate(d['directions']):
            ri=d['rows'].index(a+'_'+dd); o.paste(im.crop((0,ri*fh,fw*nf,ri*fh+fh)),(0,r*fh))
        o.save(f'{gd}/{a}.png'); o.save(f'{SC}/apv/s/{k}_{a}.webp',lossless=True,method=4)
        commit.append({'devicePath':f'C:\\Users\\easte\\OneDrive\\MAZ\\Godot\\MAJ\\Art\\ConceptRuntime\\characters\\archer\\{gk}\\{a}.png','stagedPath':f'{gd}/{a}.png'})
        pfiles[f's/{k}_{a}.webp']=f's/{k}_{a}.webp'
    ms=man['sets'][gk]; ms['frames'].update(d['frames']); ms['react']=d['react']; ms['reactGroups']=d['groups']
    st=[x for x in D['sets'] if x['id']==k][0]; st['frames'].update(d['frames']); st['react']=d['react']
    os.makedirs(f'{AN}/{k}',exist_ok=True)
    for f in glob.glob(f'{SC}/astgreact/{k}/{k}_16dir_react*'): shutil.copy(f, f'{AN}/{k}/')
    done.append(k)
man['reactNote']='2026-11-04 피격·사망·상황 동작 13종: hit_light/hit_heavy(무작위), knockback(moveBack 구간 게임이 뒤로 이동), stun(반복), death_back/front/side(무작위, 끝 유지), downed(반복), get_up, heal, potion, victory, rest(반복)'
json.dump(man,open(f'{GS}/manifest.json','w'),indent=1,ensure_ascii=False)
open(f'{SC}/apv/data.js','w').write('const DATA='+json.dumps(D,ensure_ascii=False)+';\n')
commit.append({'devicePath':'C:\\Users\\easte\\OneDrive\\MAZ\\Godot\\MAJ\\Art\\ConceptRuntime\\characters\\archer\\manifest.json','stagedPath':f'{GS}/manifest.json'})
commit.append({'devicePath':'C:\\Users\\easte\\OneDrive\\MAZ\\Godot\\MAJ\\Presentation\\ArcherSprites.cs','stagedPath':'/mnt/project-files/art/game-staging/code/ArcherSprites.cs'})
for i in range(0,len(commit),50): json.dump(commit[i:i+50],open(f'/mnt/project-files/art/game-staging/rbatch{i//50}.json','w'))
json.dump(pfiles,open(f'{SC}/apv/files10.json','w')); print(len(done), done, len(commit), len(pfiles))
