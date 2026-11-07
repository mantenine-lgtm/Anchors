set -x
cd /tmp/claude-0/-home-claude-Anchors/ef01fd61-7b0a-5f75-8c17-bcaa51a14f40/scratchpad/v7
export PYTHONDONTWRITEBYTECODE=1; rm -rf __pycache__
mkdir -p ../astganim9
for n in 1 2 3 4 5; do CELL_W=104 CELL_H=96 CELL_FOOT=82 python3 exportw.py xstage$n ../astganim9/xstage$n > ../astganim9/logx$n.txt 2>&1 & done
wait
echo ALLDONE
