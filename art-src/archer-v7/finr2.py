import json, os, glob, shutil
from PIL import Image
Image.MAX_IMAGE_PIXELS=None
SC='/tmp/claude-0/-home-claude-Anchors/ef01fd61-7b0a-5f75-8c17-bcaa51a14f40/scratchpad'
GS='/mnt/project-files/art/game-staging/archer'; AN='/mnt/project-files/art/claude-sprites/archer-stages-anim-16dir'
PC='C:\\Users\\easte\\OneDrive\\MAZ\\Godot\\MAJ\\Art\\ConceptRuntime\\characters\\archer'
OLD=['hit_light','get_up','heal']
ROWS=[['hit_front','hit_back','hit_side','hit_heavy','knockback','stun','death_front'],
      ['death_back','death_side','death_sit','downed','revive'],
      ['potion','bandage','victory','rest'],['recall']]
FW,FH=104,96
man=json.load(open(f'{GS}/manifest.json'))
s=open(f'{SC}/apv/data.js').read(); D=json.loads(s[s.index('{'):s.rstrip().rstrip(';').rindex('}')+1])
commit=[]; pfiles={'data.js':'data.js','index.html':'index.html'}; done=[]
for p in sorted(glob.glob(f'{SC}/astgreact2/*/*_16dir_react_sheet.json')):
    k=os.path.basename(p).split('_16dir')[0]; d=json.load(open(p)); im=Image.open(p.replace('.json','.png')); fw,fh=d['frameSize']
    gk=f"a{k[6:]}_crossbow" if k.startswith('xstage') else k; gd=f'{GS}/{gk}'; os.makedirs(gd,exist_ok=True)
    cut={}
    for a,nf in d['frames'].items():
        o=Image.new('RGBA',(fw*nf,fh*16),(0,0,0,0))
        for r,dd in enumerate(d['directions']):
            ri=d['rows'].index(a+'_'+dd); o.paste(im.crop((0,ri*fh,fw*nf,ri*fh+fh)),(0,r*fh))
        o.save(f'{gd}/{a}.png'); cut[a]=o
        commit.append({'devicePath':f'{PC}\\{gk}\\{a}.png','stagedPath':f'{gd}/{a}.png'})
    for a in OLD:
        for f in (f'{gd}/{a}.png', f'{SC}/apv/s/{k}_{a}.webp'):
            if os.path.exists(f): os.remove(f)
    # 미리보기 합본 시트(아티팩트 파일 수 제한)
    W=max(sum(d['frames'][a] for a in r) for r in ROWS)*FW; off={}
    out=Image.new('RGBA',(W,len(ROWS)*16*FH),(0,0,0,0))
    for bi,r in enumerate(ROWS):
        x=0
        for a in r: out.paste(cut[a],(x*FW,bi*16*FH)); off[a]=[x,bi]; x+=d['frames'][a]
    out.save(f'{SC}/apv/s/{k}_react.webp',lossless=True,quality=100,method=4); pfiles[f's/{k}_react.webp']=f's/{k}_react.webp'
    ms=man['sets'][gk]
    for a in OLD: ms['frames'].pop(a,None)
    ms['frames'].update(d['frames']); ms['react']=d['react']; ms['reactGroups']=d['groups']
    st=[x for x in D['sets'] if x['id']==k][0]
    for a in OLD: st['frames'].pop(a,None)
    st['frames'].update(d['frames']); st['react']=d['react']; st['reactSheet']=off
    os.makedirs(f'{AN}/{k}',exist_ok=True)
    for f in glob.glob(f'{SC}/astgreact2/{k}/{k}_16dir_react*'): shutil.copy(f, f'{AN}/{k}/')
    done.append(k)
# 귀환 발밑 빛(공용)
os.makedirs(f'{GS}/shared',exist_ok=True); os.makedirs(f'{AN}/shared',exist_ok=True)
for nm in ('recall_fx_back','recall_fx_front'):
    src=f'{SC}/astgreact/_fx/{nm}.png'; shutil.copy(src,f'{GS}/shared/{nm}.png'); shutil.copy(src,f'{AN}/shared/{nm}.png')
    Image.open(src).save(f'{SC}/apv/s/{nm}.webp',lossless=True,method=4); pfiles[f's/{nm}.webp']=f's/{nm}.webp'
    commit.append({'devicePath':f'{PC}\\shared\\{nm}.png','stagedPath':f'{GS}/shared/{nm}.png'})
shutil.copy(f'{SC}/astgreact/_fx/recall_fx_preview.gif',f'{AN}/shared/')
man['fx']={'recall':{'back':'shared/recall_fx_back.png','front':'shared/recall_fx_front.png','frames':36,'note':'귀환 중 캐릭터 뒤/앞에 겹쳐 그림(행=16방향 동일)'}}
man['reactNote']='2026-11-05 영웅 공통 반응 동작 16종: hit_front/hit_back/hit_side(맞은 방향, 모르면 무작위)·hit_heavy(큰 데미지)·knockback(moveBack 구간 게임이 뒤로 이동) — 전투 준비자세에서 시작·복귀. stun/downed/rest 반복, death_front/back/side/sit 무작위·끝 유지, revive는 downed에서 시작, bandage·potion·victory, recall은 24~35f 페이드+fx.recall 발밑 빛. 옛 hit_light/get_up/heal.png는 미참조.'
json.dump(man,open(f'{GS}/manifest.json','w'),indent=1,ensure_ascii=False)
open(f'{SC}/apv/data.js','w').write('const DATA='+json.dumps(D,ensure_ascii=False)+';\n')
commit.append({'devicePath':f'{PC}\\manifest.json','stagedPath':f'{GS}/manifest.json'})
commit.append({'devicePath':'C:\\Users\\easte\\OneDrive\\MAZ\\Godot\\MAJ\\Presentation\\ArcherSprites.cs','stagedPath':'/mnt/project-files/art/game-staging/code/ArcherSprites.cs'})
for f in glob.glob('/mnt/project-files/art/game-staging/rbatch*.json'): os.remove(f)
for i in range(0,len(commit),50): json.dump(commit[i:i+50],open(f'/mnt/project-files/art/game-staging/r2batch{i//50}.json','w'))
json.dump(pfiles,open(f'{SC}/apv/files11.json','w')); print(len(done), done, len(commit), len(pfiles))
