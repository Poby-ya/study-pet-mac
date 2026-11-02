#!/bin/bash
# Builds StudyPet.app (one binary for Apple silicon and Intel Macs) and StudyPet-mac.zip.
# Runs on a Mac with the Xcode command line tools; GitHub Actions runs it (ci/build.yml).
# LF line endings: macOS bash reads a CR as part of the command.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build/StudyPet.app/Contents/MacOS
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" -o "build/StudyPet-$arch" Sources/*.swift
done
lipo -create -output build/StudyPet.app/Contents/MacOS/StudyPet build/StudyPet-arm64 build/StudyPet-x86_64
cp Info.plist build/StudyPet.app/Contents/
# Ad-hoc signature: Apple silicon won't run an unsigned binary. Not notarized, which the
# one-line installer gets around (curl downloads carry no quarantine flag).
codesign --force --sign - build/StudyPet.app
(cd build && ditto -c -k --keepParent StudyPet.app StudyPet-mac.zip)
shasum -a 256 build/StudyPet-mac.zip | awk '{print $1}' > build/StudyPet-mac.zip.sha256
echo "Built: $(pwd)/build/StudyPet-mac.zip"
