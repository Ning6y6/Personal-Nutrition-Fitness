[English](README.md) | [简体中文](README.zh-CN.md)

# Evenfare / 食衡

Evenfare is my native iOS app for weighed meal logging and daily nutrition against self-set goals. I built offline food search, meal history, templates, personal food cards and validated local backup/restore for everyday cooking and repeat meals. No account is required; the current interface is Simplified Chinese.

## What works today

- **Offline food search:** 357 curated CoFID 2021 foods, searchable by Chinese name, aliases, original English name and reviewed pinyin initials.
- **Meal recording and daily totals:** multiple food items, gram-based quantities, nutrition previews, weighed/label-based or standard-portion records, and today's energy and nutrient progress. Incomplete items block saving; a day with no records does not imply zero intake.
- **History and editing:** inspect, expand, edit, delete and reuse saved meals. Changes recalculate today's totals while preserving each meal's historical nutrition basis.
- **Recent meals and templates:** start an independent draft from a recent meal or a personal template; create, rename and edit templates and their default gram quantities.
- **Personal food cards:** create and edit foods using per-100-g label values, then select them when recording meals. Saving a card alone adds no intake. Energy, fat, saturated fat, carbohydrate, sugars, protein and salt are required; fibre may remain unknown.
- **Goal history:** saved changes append versions with source, confirmation time and effective date. Changes default to tomorrow, with today or a future date available; the last confirmed version for an effective day wins. Unrecoverable past goals remain unknown.
- **Local data protection:** SwiftData storage, unsaved-input protection, versioned JSON export, validated restore into a separate store, and a recovery screen when the selected store cannot open.

## Current limits

Food cards, meals and templates use **grams**. There is no per-100-ml, scoop or serving conversion without an explicitly supported quantity model. Personal cards have no deletion, archiving or revision-history interface yet.

The Scan and Calendar tabs are placeholders. Photo estimation has contracts, persistence and an offline fixture provider, but no delivered photo-confirmation flow or real AI integration. Label OCR, barcode lookup, HealthKit, CloudKit, accounts and cross-device sync are not connected. Recipe batches, day-completeness confirmation, full calendar/trends and a complete English interface are also unimplemented. History queries are not yet paginated; no large-library performance claim is made.

## Architecture and tradeoffs

- **Domain rules stay outside the UI.** [`FoodDecisionCore`](Packages/FoodDecisionCore) contains models, validation, nutrition calculations, food search and goal selection. The app owns SwiftUI forms, SwiftData adapters, save commands and recovery. Rules remain independently testable but require explicit persistence adapters.
- **Meals keep nutrition snapshots.** Name/time edits preserve them; gram changes scale the original item's snapshot. Added/replacement foods use current values. Personal-card updates therefore cannot rewrite old meals. This duplicates data and leaves past records unchanged when the catalogue improves. See the [snapshot design and validation](docs/OPT14A_SNAPSHOT_PROTECTION_REPORT.md).
- **Unknown is not zero.** Incomplete fibre data shows coverage and a known subtotal where available, not an exact total or target gap. The other seven fields require numbers; missing source values cannot silently become zero. Arbitrary missing values for every nutrient are not yet supported.
- **New-meal saves are isolated.** A private context commits the meal and template-use increment together. Pre-commit failure rolls back only that context, preserving unrelated drafts. Stable IDs and full-content comparison let an unchanged retry verify the saved result; conflicting content is rejected. A committed save survives refresh failure. Extra reads and retry state are the cost; related unsaved changes can block saving. See the [transaction design, tests and failure cases](docs/MEAL_CREATE_TRANSACTION_REPORT.md).
- **Restore validates before switching.** JSON format 2 also reads format 1. Restore checks versions, types, IDs and relationships, writes a separate store, then closes/reopens and compares it before user-confirmed switching. The original is retained, without merging. This costs extra disk space and a confirmation step. Exports contain personal data and image references, not image bytes; JSON has no app-level password encryption. See the [goal-history migration and backup validation](docs/OPT09_GOAL_HISTORY_REPORT.md) and [restore implementation](FoodDecisionAssistant/Persistence/LocalStoreBackupService.swift).

The current store is [Schema V2, version 2.0.0](FoodDecisionAssistant/Persistence/VersionedSchemaV2.swift): the frozen twelve-entity V1 plus one goal-version entity, **13 entities in total**. Local uniqueness constraints remain, CloudKit is disabled, and unknown historical schemas are not automatically guessed or replaced. The app identity remains `com.ning6y6.ShiHeng`.

## Build and run

Requirements: macOS 26 or later for the Core package, Xcode with the required iOS SDK/runtime, and Swift tools 6.2 or later. The project uses Swift 6 language mode and targets **iOS 26.0+**. The recorded development toolchain is **Xcode 27.0 / Apple Swift 6.4**; this is not a claim that every supported OS/device combination has been tested.

From the repository root:

```sh
open FoodDecisionAssistant.xcodeproj
```

Select the shared **FoodDecisionAssistant** scheme, choose an iPhone simulator and run. For a physical iPhone, choose your signing team and device in Xcode. Update the existing installation to retain local records; do not uninstall or clear its store. The built product is `ShiHeng.app`.

To compile for the simulator without choosing a particular device:

```sh
SHIHENG_SIMULATOR_DESTINATION='generic/platform=iOS Simulator' ./scripts/build-ios.sh
```

The script disables code signing for simulator builds. No food API key or backend setup is required.

## Tests

Run domain tests independently:

```sh
swift test --package-path Packages/FoodDecisionCore
```

**Use a dedicated QA iPhone simulator containing only synthetic data for App/UI tests.** UI tests launch the ordinary app and create, edit and delete records; some goal versions and personal cards remain afterward. The scripts do not isolate the app's data and otherwise auto-select an available simulator, preferring a booted device. Do not point them at an everyday simulator containing personal records or at a physical device.

List available simulators, replace `QA_SIMULATOR_UDID` with the dedicated simulator's UUID, then run:

```sh
xcrun simctl list devices available
export SHIHENG_SIMULATOR_DESTINATION='platform=iOS Simulator,id=QA_SIMULATOR_UDID'

./scripts/test-ios.sh -only-testing:FoodDecisionAssistantTests \
  -parallel-testing-enabled NO -collect-test-diagnostics never

./scripts/test-ios.sh -only-testing:FoodDecisionAssistantUITests \
  -parallel-testing-enabled NO -collect-test-diagnostics never
```

App tests need an installed iOS simulator runtime; UI tests also need an awake Mac and an available simulator UI. UI cases that check text-size or appearance behavior require the matching simulator settings. Simulator results do not replace physical-device, VoiceOver or external-keyboard acceptance.

## Food data and attribution

The bundled catalogue is a **357-food subset of [CoFID 2021](https://www.gov.uk/government/publications/composition-of-foods-integrated-dataset-cofid)**, not the full source database or a branded-product/barcode database. Catalogue version: `cofid-2021-zh-v1`; import rules: `food-import-cofid-2021-v1`.

A [reviewed selection file](data/food-catalog/cofid-2021-curation.json) and [importer](scripts/import_cofid.py) check the official workbook's hash, food identities and measurement basis. The selection adds Chinese search terms while keeping raw/cooked and food-part distinctions between entries. Ambiguous identities and missing required values are quarantined; the original 12 entries retain their IDs and values. The workbook is not committed.

- Energy and carbohydrate retain CoFID's definitions; energy is not recomputed using 4/9/4, and carbohydrate/sugars use monosaccharide equivalents rather than being assumed identical to packaging labels.
- Trace (`Tr`) is a documented calculation approximation of zero; `N` and blank cells are unavailable. Unknown AOAC fibre stays unknown and is not replaced by NSP fibre. Sodium is converted to salt as `sodium mg / 1000 × 2.5`.
- Only a per-100-g food basis enters the current meal calculation. Brand recipes and cooking methods can differ from the selected generic food; generic meat entries do not certify halal status. The app records nutrition and user-set goals, not verified medical outcomes or food-safety guarantees.

Public Health England (2021). McCance and Widdowson’s The Composition of Foods Integrated Dataset (CoFID). Contains public sector information licensed under the [Open Government Licence v3.0](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/).

Full selection, exclusions, modifications and provenance: [catalogue audit](docs/OPT12_CATALOG_AUDIT.md), [import rules](docs/OPT12_FOOD_IMPORT_RULES.md), and [catalogue manifest](data/food-catalog/catalog-manifest-v1.json). The app also includes a Data Sources and Licences page.

## Validation and next steps

The [latest recorded code-change validation](docs/MEAL_CREATE_TRANSACTION_REPORT.md), dated **2026-10-23** and delivered as commit `57ff859`, reports:

| Suite | Test declarations | Executions |
| --- | ---: | ---: |
| FoodDecisionCore | 183 | 685 |
| App unit tests | 359 | 901 |
| Selected UI regression cases | 8 | 8 |

Declarations count each parameterized test once; executions count its input cases separately. UI numbers cover selected cases only. The final build passed. The report preserves an intermittent existing migration-test failure and subsequent isolated/full passes; its cause remains unresolved. These are recorded results, **not tests rerun for this README-only update**. Physical acceptance steps and evidence limits are in the reports; [personal food-card validation](docs/OPT13_PERSONAL_FOOD_REPORT.md) is recorded separately.

Next planned work is recipe batches and portion allocation, followed by day confirmation, bounded history queries and calendar/trend views. Photo confirmation, real AI, label scanning and HealthKit remain separate future work; cloud sync is only a later consideration. See the [longer-term roadmap](docs/ROADMAP.md), which also retains historical milestone notes. Future work requires its own scope and validation; the feature list above describes the current implementation.
