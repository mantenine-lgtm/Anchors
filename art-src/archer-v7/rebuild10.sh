set -x
cd /tmp/claude-0/-home-claude-Anchors/ef01fd61-7b0a-5f75-8c17-bcaa51a14f40/scratchpad/v7
export PYTHONDONTWRITEBYTECODE=1 CELL_W=104 CELL_H=96 CELL_FOOT=82; rm -rf __pycache__
SETS="a2_shortbow a3_shortbow a4_shortbow a5_shortbow a1_bow a2_bow a3_bow a4_bow a5_bow a1_longbow a2_longbow a3_longbow a4_longbow a5_longbow a1_runebow a2_runebow a3_runebow a4_runebow a5_runebow xstage1 xstage2 xstage3 xstage4 xstage5"
echo $SETS | tr ' ' '\n' | xargs -P 4 -I{} sh -c 'python3 exportr.py {} ../astgreact/{} > ../astgreact/log_{}.txt 2>&1'
echo ALLDONE
