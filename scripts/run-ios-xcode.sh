#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
action="${1:?Specify build or test}"
shift
case "$action" in
  build|test) ;;
  *) printf 'Unsupported action: %s\n' "$action" >&2; exit 2 ;;
esac

destination="${SHIHENG_SIMULATOR_DESTINATION:-}"
if [[ -z "$destination" ]]; then
  simulator_id="$(xcrun simctl list devices available --json | /usr/bin/perl -MJSON::PP -0ne '
    my $catalog = decode_json($_);
    my @phones;
    for my $runtime (reverse sort keys %{$catalog->{devices}}) {
      next unless $runtime =~ /iOS/;
      my @available = grep { $_->{isAvailable} && $_->{name} =~ /^iPhone/ } @{$catalog->{devices}{$runtime}};
      push @phones, sort { ($b->{state} eq "Booted") <=> ($a->{state} eq "Booted") || $a->{name} cmp $b->{name} } @available;
    }
    die "No available iPhone simulator\n" unless @phones;
    print $phones[0]->{udid};
  ')"
  destination="platform=iOS Simulator,id=$simulator_id"
fi

printf 'ShiHeng %s on %s\n' "$action" "$destination"
exec xcodebuild \
  -project "$project_root/FoodDecisionAssistant.xcodeproj" \
  -scheme FoodDecisionAssistant \
  -destination "$destination" \
  -derivedDataPath "${SHIHENG_DERIVED_DATA_PATH:-$project_root/.build/DerivedData}" \
  CODE_SIGNING_ALLOWED=NO \
  "$action" "$@"
