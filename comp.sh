# When switching between modes, add -B as an argument to rebuild all code
mode="d64"

# Normal:
if [ "$mode" = "32" ]; then fpc -CX -XXs- -O3oloopunroll,deadstore -OpPentium3 -CpPentium $*; fi
if [ "$mode" = "64" ]; then fpc -CX -XXs- -O3oloopunroll,deadstore -CpAthlon64 $*; fi

# Full-program optimised:
if [ "$mode" = "fpo32" ]; then
fpc -FWopti.dat -CX -XXs- -O3oloopunroll,deadstore -OWall -OpPentium3 -CpPentium $*
fpc -Fwopti.dat -CX -XXs -O3oloopunroll,deadstore -Owall -OpPentium3 -CpPentium $*
if [-e opti.dat]; then rm opti.dat; fi
fi

if [ "$mode" = "fpo64" ]; then
fpc -FWopti.dat -CX -XXs- -O3oloopunroll,deadstore -OWall -CpAthlon64 $*
fpc -Fwopti.dat -CX -XXs -O3oloopunroll,deadstore -Owall -CpAthlon64 $*
if [-e opti.dat]; then rm opti.dat; fi
fi

# Debug: (-gc not supported yet)
if [ "$mode" = "d32" ]; then fpc -ghlt -vwinh -XXs- -Cotr -O3odeadstore -OpPentium3 -CpPentium $*; fi
if [ "$mode" = "d64" ]; then fpc -ghlt -vwinh -XXs- -Cotr -O3odeadstore -CpAthlon64 $*; fi
