@echo off
echo ----------------------------------------------------------------------

REM Ask the compiler how many bits we're targeting
for /F "delims=" %%A in ('fpc -iTP') do set tcpu=%%A
if %tcpu%==i386 set bits=32
if %tcpu%==x86_64 set bits=64

REM Check commandline's first parameter for -n -f -d mode, -d is default
set mode=d%bits%
if "%1"=="-n" (
  set mode=n%bits%
  shift
)
if "%1"=="-f" (
  set mode=fpo%bits%
  shift
)
if "%1"=="-d" (
  set mode=d%bits%
  shift
)

echo Compile mode: %mode%

REM When switching between modes, add -B as an argument to rebuild all code

REM Normal:
if %mode%==n32 fpc -CX -XXs- -O3oloopunroll,deadstore -OpPentium3 -CpPentium %1 %2 %3 %4
if %mode%==n64 fpc -CX -XXs- -O3oloopunroll,deadstore -CpAthlon64 %1 %2 %3 %4

REM Full-program optimised:
if %mode%==fpo32 (
fpc -FWopti.dat -CX -XXs- -O3oloopunroll,deadstore -OWall -OpPentium3 -CpPentium %1 %2 %3 %4
fpc -Fwopti.dat -CX -XXs -O3oloopunroll,deadstore -Owall -OpPentium3 -CpPentium %1 %2 %3 %4
if exist opti.dat del opti.dat 1>nul
)

if %mode%==fpo64 (
fpc -FWopti.dat -CX -XXs- -O3oloopunroll,deadstore -OWall -CpAthlon64 %1 %2 %3 %4
fpc -Fwopti.dat -CX -XXs -O3oloopunroll,deadstore -Owall -CpAthlon64 %1 %2 %3 %4
if exist opti.dat del opti.dat 1>nul
)

REM Debug: (add -gc in FPC304+, see if still crashes unit compilation)
if %mode%==d32 fpc -ghlt -vwinh -XXs- -Cotr -O3odeadstore -OpPentium3 -CpPentium %1 %2 %3 %4
if %mode%==d64 fpc -ghlt -vwinh -XXs- -Cotr -O3odeadstore -CpAthlon64 %1 %2 %3 %4

