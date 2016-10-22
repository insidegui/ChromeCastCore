#!/bin/bash

echo -e "\n\033[1;31mIMPORTANT: To build this project you need automake, libtool and protobuf.\nYou can install them easily with Homebrew:\n"
echo -e "\033[1;34mbrew install automake libtool protobuf\n\n\033[0m"

cd Vendor/Protobuf
./scripts/build.sh
cd ../..