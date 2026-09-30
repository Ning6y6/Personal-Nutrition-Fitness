#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"

xcodebuild \
  -project "$project_root/FoodDecisionAssistant.xcodeproj" \
  -scheme FoodDecisionAssistant \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \
  -derivedDataPath "$project_root/.build/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build

