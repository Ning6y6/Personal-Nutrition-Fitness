# Project guidance

- This is a personal-use native iOS app built with SwiftUI and Swift 6.
- Keep health and dietary rules deterministic, versioned, and testable. LLM output must never bypass hard constraints.
- Put pure domain models and rule logic in `Packages/FoodDecisionCore`.
- Put Apple-framework adapters such as HealthKit and SwiftData in the app target.
- Do not add third-party dependencies unless they materially reduce risk and are explicitly justified.
- Validate domain changes with `swift test --package-path Packages/FoodDecisionCore`.
- Validate app changes with `./scripts/build-ios.sh`.
- Never commit API keys, signing certificates, provisioning profiles, or personal health exports.

