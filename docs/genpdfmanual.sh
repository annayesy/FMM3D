#!/bin/bash
# This makes the PDF manual then moves it and renames to the top directory.
# Barnett 12/6/17

make latexpdf
mv _build/latex/fmm3d.pdf ../fmm3d_manual.pdf
