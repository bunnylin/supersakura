echo ----------------------------------------------------------------

# Ask the compiler how many bits we're targeting
TCPU="$(fpc -iTP)"
if [ "$TCPU" = "i386" ]; then BITS=32; fi
if [ "$TCPU" = "x86_64" ]; then BITS=64; fi

# Check commandline's first parameter for -n -f -d mode, -d is default

mode=d$BITS
if [ "$1" = "-n" ]; then mode=n$BITS; shift; fi
if [ "$1" = "-f" ]; then mode=fpo$BITS; shift; fi
if [ "$1" = "-d" ]; then mode=d$BITS; shift; fi

echo "Compile mode: $mode"

# When switching between modes, add -B as an argument to rebuild all code

# Normal:
if [ "$mode" = "n32" ]; then fpc -CX -XXs- -O3oloopunroll,deadstore -OpPentium3 -CpPentium $1 $2 $3 $4; fi
if [ "$mode" = "n64" ]; then fpc -CX -XXs- -O3oloopunroll,deadstore -CpAthlon64 $1 $2 $3 $4; fi

# Full-program optimised:
if [ "$mode" = "fpo32" ]; then
fpc -FWopti.dat -CX -XXs- -O3oloopunroll,deadstore -OWall -OpPentium3 -CpPentium $1 $2 $3 $4
fpc -Fwopti.dat -CX -XXs -O3oloopunroll,deadstore -Owall -OpPentium3 -CpPentium $1 $2 $3 $4
if [ -e opti.dat ]; then rm opti.dat; fi
fi

if [ "$mode" = "fpo64" ]; then
fpc -FWopti.dat -CX -XXs- -O3oloopunroll,deadstore -OWall -CpAthlon64 $1 $2 $3 $4
fpc -Fwopti.dat -CX -XXs -O3oloopunroll,deadstore -Owall -CpAthlon64 $1 $2 $3 $4
if [ -e opti.dat ]; then rm opti.dat; fi
fi

# Debug: (-gc not supported yet)
if [ "$mode" = "d32" ]; then fpc -ghlt -vwinh -XXs- -Cotr -O3odeadstore -OpPentium3 -CpPentium $1 $2 $3 $4; fi
if [ "$mode" = "d64" ]; then fpc -ghlt -vwinh -XXs- -Cotr -O3odeadstore -CpAthlon64 $1 $2 $3 $4; fi
