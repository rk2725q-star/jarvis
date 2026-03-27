#!/bin/bash

# 1. Install Flutter (Skip if already there)
if [ ! -d "flutter" ]; then
    echo "Cloning Flutter stable channel..."
    git clone https://github.com/flutter/flutter.git -b stable --depth 1
fi

export PATH="$PATH:`pwd`/flutter/bin"
export FLUTTER_ROOT_USER=1

# 2. Configure for Web
flutter config --enable-web

# 3. Build the web app with injected keys for Vercel
echo "Building Flutter Web with environment variables..."
flutter build web --release \
  --dart-define=GOOGLE_SERVICE_ACCOUNT="$GOOGLE_SERVICE_ACCOUNT" \
  --dart-define=NVIDIA_API_KEY="$NVIDIA_API_KEY" \
  --dart-define=OLLAMA_CLOUD_API_KEY="$OLLAMA_CLOUD_API_KEY" \
  --dart-define=GEMINI_API_KEY="$GEMINI_API_KEY" \
  --no-pub --tree-shake-icons

echo "Build completed successfully!"
