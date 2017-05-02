@echo off
echo ----------------------------------------------------------------------
set mode=d32

REM When switching between modes, add -B as an argument to rebuild all code

REM Normal:
if %mode%==32 fpc -CX -XXs- -O3oloopunroll,deadstore -OpPentium3 -CpPentium %*
if %mode%==64 fpc -CX -XXs- -O3oloopunroll,deadstore -CpAthlon64 %*

REM Full-program optimised:
if %mode%==fpo32 (
fpc -FWopti.dat -CX -XXs- -O3oloopunroll,deadstore -OWall -OpPentium3 -CpPentium %*
fpc -Fwopti.dat -CX -XXs -O3oloopunroll,deadstore -Owall -OpPentium3 -CpPentium %*
if exist opti.dat del opti.dat 1>nul
)

if %mode%==fpo64 (
fpc -FWopti.dat -CX -XXs- -O3oloopunroll,deadstore -OWall -CpAthlon64 %*
fpc -Fwopti.dat -CX -XXs -O3oloopunroll,deadstore -Owall -CpAthlon64 %*
if exist opti.dat del opti.dat 1>nul
)

REM Debug: (add -gc in FPC304+, see if still crashes unit compilation)
if %mode%==d32 fpc -ghlt -vwinh -XXs- -Cotr -O3odeadstore -OpPentium3 -CpPentium %*
if %mode%==d64 fpc -ghlt -vwinh -XXs- -Cotr -O3odeadstore -CpAthlon64 %*

