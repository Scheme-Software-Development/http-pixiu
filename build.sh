if [ -d "./socket" ]; then
    echo "skip"
else
    mkdir socket
fi

# Apply patch for ufo-socket writer fix
if [ -f "./patches/ufo-socket-writer-fix.patch" ]; then
    patch -N -p1 -d .akku/lib/ufo-socket/ < ./patches/ufo-socket-writer-fix.patch 2>/dev/null || true
fi

cd .akku/src/ufo-socket/
make

mv socket/*.o ../../../socket/
mv socket/*.so ../../../socket/