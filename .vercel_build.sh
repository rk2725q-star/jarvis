#!/bin/bash

# 1. Install Flutter
if [ ! -d "flutter" ]; then
    git clone https://github.com/flutter/flutter.git -b stable
fi
export PATH="$PATH:`pwd`/flutter/bin"

# 2. Pre-download dependencies
flutter precache --web

# 3. Upgrade and build
flutter build web --release --no-pub
