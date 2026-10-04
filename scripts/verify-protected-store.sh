#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
source_directory="${1:?Pass the protected directory containing default.store and its sidecars}"
[[ -d "$source_directory" && -f "$source_directory/default.store" ]] || {
  printf 'Protected store directory is missing\n' >&2; exit 2;
}
# The sample is never opened directly or put in the repository. Nothing is deleted.
probe_directory="$(mktemp -d /private/tmp/shiheng-store-probe.XXXXXX)"
core_products="$project_root/Packages/FoodDecisionCore/.build/debug"
swift test --package-path "$project_root/Packages/FoodDecisionCore"
swiftc -swift-version 6 -parse-as-library -module-name FoodDecisionAssistant \
  -I "$core_products" -L "$core_products" -lFoodDecisionCore \
  -module-cache-path "$project_root/.build/ProbeModules" \
  "$project_root/FoodDecisionAssistant/Persistence/VersionedSchemaV1.swift" \
  "$project_root/FoodDecisionAssistant/Persistence/MealTemplatePersistence.swift" \
  "$project_root/FoodDecisionAssistant/Persistence/ShiHengMigrationPlan.swift" \
  "$project_root/FoodDecisionAssistant/Persistence/StoreSchemaCompatibility.swift" \
  "$project_root/FoodDecisionAssistant/Persistence/LocalStoreBackup.swift" \
  "$project_root/FoodDecisionAssistant/Persistence/LocalStoreBackupService.swift" \
  "$project_root/FoodDecisionAssistant/Persistence/LocalStoreBackupRestoration.swift" \
  "$project_root/FoodDecisionAssistant/Persistence/LocalStorePathValidator.swift" \
  "$project_root/FoodDecisionAssistant/Persistence/LocalStoreBootstrap.swift" \
  "$project_root/scripts/StoreProtectionProbe.swift" \
  -o "$probe_directory/probe"
"$probe_directory/probe" "$source_directory" "$probe_directory/result"
printf 'Private verification output (never commit): %s\n' "$probe_directory/result"
