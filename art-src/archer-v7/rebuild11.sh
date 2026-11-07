#!/bin/bash
cd /tmp/claude-0/-home-claude-Anchors/ef01fd61-7b0a-5f75-8c17-bcaa51a14f40/scratchpad
export PYTHONDONTWRITEBYTECODE=1 CELL_W=104 CELL_H=96 CELL_FOOT=82
mkdir -p astgreact2
SETS="a1_shortbow a1_bow a1_longbow a1_runebow a2_shortbow a2_bow a2_longbow a2_runebow a3_shortbow a3_bow a3_longbow a3_runebow a4_shortbow a4_bow a4_longbow a4_runebow a5_shortbow a5_bow a5_longbow a5_runebow xstage1 xstage2 xstage3 xstage4 xstage5"
echo $SETS | tr ' ' '\n' | xargs -P 4 -I{} sh -c 'REUSE=astgreact/{} python3 v7/exportr.py {} astgreact2/{} > astgreact2/log_{}.txt 2>&1'
echo ALLDONE > astgreact2/ALLDONE
