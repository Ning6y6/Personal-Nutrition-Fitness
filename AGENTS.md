# Project guidance

- This is a personal-use native iOS app built with SwiftUI and Swift 6.
- Keep health and dietary rules deterministic, versioned, and testable. LLM output must never bypass hard constraints.
- Put pure domain models and rule logic in `Packages/FoodDecisionCore`.
- Put Apple-framework adapters such as HealthKit and SwiftData in the app target.
- Do not add third-party dependencies unless they materially reduce risk and are explicitly justified.
- Validate domain changes with `swift test --package-path Packages/FoodDecisionCore`.
- Validate app changes with `./scripts/build-ios.sh`.
- Never commit API keys, signing certificates, provisioning profiles, or personal health exports.

# Delivery and approved scope

- The approved execution order is in `docs/OPTIMIZATION_EXECUTION_PLAN.md`: S0, then S1 data protection, then S2 correctness. Do not bypass a stage gate or begin S3–S5 without user approval.
- Support individual local use, including one or two friends with their own local data. This does not authorize shared accounts, cloud sync, a backend, or removing local uniqueness constraints.
- Use purpose-specific branches: `feat/<task>` for new behavior, `fix/<task>` for defects, `refactor/<task>` for behavior-preserving restructuring, `docs/<task>` for documentation, and `test/<task>` for test-only work. Do not label feature or bug changes as refactors.
- Keep each OPT task in an independently verifiable commit; do not mix a completed feature baseline with subsequent optimization work.
- Push validated task branches and integrate using non-destructive fast-forward merges where possible; never force-push or rewrite existing history without explicit approval.
- Physical-device data and protected database samples must stay outside Git and must never appear in logs or test fixtures. Do not uninstall the physical app or clear its store to resolve compatibility problems.
- Brand, naming, icon, palette and UI-review outcomes are recorded in `docs/BRAND_UI_DECISIONS.md`. Only items marked 已确认 there are decisions; items marked 建议（待确认）or 待决 are not approved for implementation. Never change the bundle ID `com.ning6y6.ShiHeng`.
