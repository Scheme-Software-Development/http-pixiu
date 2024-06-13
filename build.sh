if [ -d "./socket" ]; then
    echo "skip"
else
    mkdir socket
fi

cd .akku/src/ufo-socket/
make

mv socket/*.o ../../../socket/
mv socket/*.so ../../../socket/