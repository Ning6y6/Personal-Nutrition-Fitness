#!/usr/bin/env python3
"""Reproduce the frozen public CoFID catalog without network or third-party packages.

Usage: python3 scripts/import_cofid.py /path/to/official-2021.xlsx [--check]
The original workbook stays outside Git. --check never changes generated files.
"""
from __future__ import annotations

import argparse
from collections import Counter
from decimal import Decimal, InvalidOperation
import hashlib
import json
from pathlib import Path
import re
import sys
import uuid
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CURATION = ROOT / "data/food-catalog/cofid-2021-curation.json"
CATALOG = ROOT / "Packages/FoodDecisionCore/Sources/FoodDecisionCore/Resources/food-catalog-v1.json"
MANIFEST = ROOT / "data/food-catalog/catalog-manifest-v1.json"
VERSION = "cofid-2021-zh-v1"
RULE_VERSION = "food-import-cofid-2021-v1"
SOURCE_URL = "https://www.gov.uk/government/publications/composition-of-foods-integrated-dataset-cofid"
NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
REL_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
CATEGORIES = {"protein_main", "staple_grain", "mixed_meal", "snack_dessert", "beverage", "oil", "sauce"}
LEGACY_IDS = {
    "11-862": "20000000-0000-4000-8000-000000011862",
    "13-517": "20000000-0000-4000-8000-000000013517",
    "12-937": "20000000-0000-4000-8000-000000012937",
    "13-318": "20000000-0000-4000-8000-000000013318",
    "13-161": "20000000-0000-4000-8000-000000013161",
    "13-570": "20000000-0000-4000-8000-000000013570",
    "18-006": "20000000-0000-4000-8000-000000018006",
    "18-020": "20000000-0000-4000-8000-000000018020",
    "18-323": "20000000-0000-4000-8000-000000018323",
    "18-319": "20000000-0000-4000-8000-000000018319",
    "17-041": "20000000-0000-4000-8000-000000017041",
    "17-721": "20000000-0000-4000-8000-000000017721",
}
# Each mapping freezes source code, unit and basis independently of column order.
FIELDS = {
    "KCALS": ("1.3 Proximates", "kcal", "per100gFood", "来源热量；不加纤维能量", 10),
    "KJ": ("1.3 Proximates", "kJ", "per100gFood", "来源千焦；不当作kcal", 11),
    "PROT": ("1.3 Proximates", "g", "per100gFood", "来源蛋白，按原氮换算系数", 10),
    "FAT": ("1.3 Proximates", "g", "per100gFood", "总脂肪，不等于脂肪酸之和", 10),
    "SATFOD": ("1.3 Proximates", "g", "per100gFood", "每100g食品的饱和脂肪酸", 11),
    "CHO": ("1.3 Proximates", "g", "per100gFood", "可利用碳水，单糖当量，不含纤维", 10),
    "TOTSUG": ("1.3 Proximates", "g", "per100gFood", "总糖，单糖当量，不含寡糖", 11),
    "NA": ("1.4 Inorganics", "mg", "per100gFood", "钠；盐g=钠mg/1000*2.5", 12),
    "AOACFIB": ("1.3 Proximates", "g", "per100gFood", "AOAC纤维；不以NSP替代", 11),
    "ENGFIB": ("1.3 Proximates", "g", "per100gFood", "NSP，非淀粉多糖", 11),
    "RET": ("1.5 Vitamins", "µg", "per100gFood", "全反式视黄醇当量；不是总维生素A", 12),
    "CAREQU": ("1.5 Vitamins", "µg", "per100gFood", "β-胡萝卜素当量", 12),
    "RETEQU": ("1.5 Vitamins", "µg", "per100gFood", "总RE；不是RAE", 13),
    "CHOL": ("1.3 Proximates", "mg", "per100gFood", "胆固醇", 12),
    "FODTRANS": ("1.3 Proximates", "g", "per100gFood", "总反式脂肪酸；已在对应MUFA/PUFA内", 11),
    "MONOFOD": ("1.3 Proximates", "g", "per100gFood", "总单不饱和脂肪酸，含其反式成分", 11),
    "POLYFOD": ("1.3 Proximates", "g", "per100gFood", "总多不饱和脂肪酸，含其反式成分", 11),
    "MONOFODc": ("1.3 Proximates", "g", "per100gFood", "顺式单不饱和脂肪酸", 11),
    "POLYFODc": ("1.3 Proximates", "g", "per100gFood", "顺式多不饱和脂肪酸", 11),
    "ALCO": ("1.3 Proximates", "g", "sourceBasis", "酒精；酒精饮料原基准为100ml", 11),
    "STAR": ("1.3 Proximates", "g", "per100gFood", "淀粉单糖当量，含糊精、不含抗性淀粉", 11),
    "OLIGO": ("1.3 Proximates", "g", "per100gFood", "寡糖单糖当量", 11),
}
LEGACY_SNAPSHOT_SHA256 = "d3c7e6e1d5a9f0970f89f7c98b811a0c6b924f3517bd7e48cfba0450435d9aa3"
REQUIRED = {
    "energyKcal": "KCALS", "fatGrams": "FAT", "saturatedFatGrams": "SATFOD",
    "carbohydrateGrams": "CHO", "sugarGrams": "TOTSUG", "proteinGrams": "PROT",
}


class CatalogImportError(ValueError):
    pass


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8")


def scalar(raw: str, *, required=True):
    """Trace is a documented calculation approximation; unavailable stays unavailable."""
    value = raw.strip()
    if value == "Tr":
        return Decimal(0)
    if value in ("", "N"):
        if required:
            raise CatalogImportError("required nutrient is unknown: " + repr(raw))
        return None
    try:
        result = Decimal(value)
    except InvalidOperation as error:
        raise CatalogImportError("unrecognized nutrient: " + repr(raw)) from error
    if not result.is_finite() or result < 0:
        raise CatalogImportError("nutrient must be finite and nonnegative: " + repr(raw))
    return result


def nutrients(raw, basis):
    if basis != "per100gFood":
        raise CatalogImportError("unsupported food basis: " + basis)
    result = {target: float(scalar(raw[code])) for target, code in REQUIRED.items()}
    result["saltGrams"] = float(scalar(raw["NA"]) / Decimal(1000) * Decimal("2.5"))
    fibre = scalar(raw["AOACFIB"], required=False)
    result["fibreGrams"] = None if fibre is None else float(fibre)
    return result


def validate_curation(rows):
    if len({x["code"] for x in rows}) != len(rows):
        raise CatalogImportError("duplicate curated source code")
    if set(x["code"] for x in rows if "legacyFood" in x) != set(LEGACY_IDS):
        raise CatalogImportError("all and only the original 12 legacy records are required")
    legacy_by_code = {x["code"]: x["legacyFood"] for x in rows if "legacyFood" in x}
    legacy_snapshot = [legacy_by_code[code] for code in LEGACY_IDS]
    legacy_digest = hashlib.sha256(json.dumps(legacy_snapshot, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")).hexdigest()
    if legacy_digest != LEGACY_SNAPSHOT_SHA256:
        raise CatalogImportError("original 12 legacy fields differ from baseline 6990010")
    for row in rows:
        if row["category"] not in CATEGORIES:
            raise CatalogImportError("invalid category: " + row["code"])
        if not row["name"].strip() or not row["foodState"].strip():
            raise CatalogImportError("missing reviewed name/state: " + row["code"])
        if not row["pinyinInitials"] or any(not re.fullmatch(r"[a-z]+", x) for x in row["pinyinInitials"]):
            raise CatalogImportError("invalid frozen pinyin initials: " + row["code"])
        if len(set(row["aliases"])) != len(row["aliases"]) or any(not x.strip() for x in row["aliases"]):
            raise CatalogImportError("invalid aliases: " + row["code"])
        legacy = row.get("legacyFood")
        if legacy:
            expected = LEGACY_IDS[row["code"]]
            if legacy["id"].lower() != expected or legacy["name"] != row["name"] or legacy["category"] != row["category"]:
                raise CatalogImportError("legacy identity differs: " + row["code"])
            if legacy["unit"] != "g" or legacy["source"] != f"CoFID 2021 · {row['code']} · 每 100 g；Tr 按 0 计，盐=钠×2.5":
                raise CatalogImportError("legacy unit/source differs: " + row["code"])


def read_workbook(path):
    """Read source cells, never recalculate or edit the original workbook."""
    with zipfile.ZipFile(path) as archive:
        strings = ["".join(x.itertext()) for x in ET.fromstring(archive.read("xl/sharedStrings.xml"))]
        rels = {x.attrib["Id"]: x.attrib["Target"] for x in ET.fromstring(archive.read("xl/_rels/workbook.xml.rels"))}
        sheets = {}
        for sheet in ET.fromstring(archive.read("xl/workbook.xml")).find("m:sheets", NS):
            name = sheet.attrib["name"]
            if name not in {x[0] for x in FIELDS.values()} | {"1.1 Notes", "1.2 Factors"}:
                continue
            member = rels[sheet.attrib["{" + REL_NS + "}id"]].lstrip("/")
            if not member.startswith("xl/"):
                member = "xl/" + member
            rows = {}
            for row in ET.fromstring(archive.read(member)).findall("m:sheetData/m:row", NS):
                cells = {}
                for cell in row:
                    if cell.find("m:f", NS) is not None:
                        raise CatalogImportError("unexpected source formula: " + name + "/" + cell.attrib["r"])
                    value = cell.find("m:v", NS)
                    if value is not None:
                        column = re.sub(r"[0-9]", "", cell.attrib["r"])
                        cells[column] = strings[int(value.text)] if cell.attrib.get("t") == "s" else value.text
                rows[int(row.attrib["r"])] = cells
            sheets[name] = rows
    notes = sheets["1.1 Notes"]
    if "alcoholic beverages" not in notes[4]["A"] or "100g Fatty Acid" not in notes[4]["A"]:
        raise CatalogImportError("source basis notes changed")
    source_columns = {}
    for code, (sheet, unit, basis, definition, page) in FIELDS.items():
        columns = [column for column, field in sheets[sheet][2].items() if field == code]
        if len(columns) != 1:
            raise CatalogImportError("missing or duplicate field: " + code)
        column = columns[0]
        header = sheets[sheet][1].get(column, "")
        if not header.endswith("(" + unit + ")"):
            raise CatalogImportError("unit/header mismatch: " + code + "/" + header)
        source_columns[code] = {"worksheet": sheet, "column": column, "unit": unit, "basis": basis,
                                "definition": definition, "guidePrintedPage": page}
    return sheets, source_columns


def source_records(sheets, columns):
    primary = sheets["1.3 Proximates"]
    data_rows = {row: cells for row, cells in primary.items() if row >= 4 and cells.get("A")}
    counts = Counter(cells["A"] for cells in data_rows.values())
    duplicate_rows = [{"row": row, "code": cells["A"], "name": cells["B"], "reason": "duplicateSourceCode"}
                      for row, cells in data_rows.items() if counts[cells["A"]] != 1]
    records = {}
    for row, cells in data_rows.items():
        if counts[cells["A"]] != 1:
            continue
        raw = {}
        for code, field in columns.items():
            other = sheets[field["worksheet"]].get(row, {})
            if other.get("A") != cells["A"] or other.get("B") != cells["B"]:
                raise CatalogImportError("cross-sheet identity mismatch at row " + str(row))
            raw[code] = other.get(field["column"], "")
        records[cells["A"]] = {"row": row, "name": cells["B"], "description": cells.get("C", ""),
                               "group": cells.get("D", ""), "references": cells.get("F", ""),
                               "footnote": cells.get("G", ""), "raw": raw}
    return records, duplicate_rows, len(data_rows)


def make_entry(review, record):
    code = review["code"]
    if review["originalName"] != record["name"] or review["sourceRow"] != record["row"]:
        raise CatalogImportError("frozen source identity changed: " + code)
    # Q is the alcoholic beverage group. 'weighed with/as served' uses an inedible
    # weight basis and is deliberately excluded instead of guessing an edible factor.
    name_lower = record["name"].lower()
    if record["group"].startswith("Q") or "weighed " in name_lower:
        raise CatalogImportError("non per-100g-food edible basis: " + code)
    if re.search(r"\b(pork|bacon|gammon|gelatine|gelatin|lard)\b", name_lower):
        raise CatalogImportError("excluded ingredient: " + code)
    if re.search(r"\b(wine|beer|liqueur|cider|rum|brandy|sherry)\b", name_lower):
        raise CatalogImportError("alcohol ingredient requires exclusion: " + code)
    legacy = review.get("legacyFood")
    if legacy:
        food = legacy
    else:
        food = {"id": str(uuid.uuid5(uuid.NAMESPACE_URL, SOURCE_URL + "#2021:" + code)),
                "name": review["name"], "category": review["category"],
                "nutrientsPer100Units": nutrients(record["raw"], "per100gFood"), "unit": "g",
                "source": f"CoFID 2021 · {code} · 每 100 g；碳水/糖为单糖当量，Tr 按 0 计，盐=钠×2.5"}
    entry = {"food": food, "code": code, "originalName": record["name"], "aliases": review["aliases"],
             "pinyinInitials": review["pinyinInitials"], "foodState": review["foodState"],
             "basis": "per100gFood", "sourceRow": record["row"], "rawNutrients": record["raw"],
             "legacySeed": bool(legacy), "sourceDescription": record["description"],
             "sourceGroup": record["group"], "sourceReferences": record["references"],
             "sourceFootnote": record["footnote"]}
    if legacy:
        try:
            source_values = nutrients(record["raw"], "per100gFood")
            differences = {key: {"legacyPublished": value, "currentSourceProjection": source_values[key]}
                           for key, value in legacy["nutrientsPer100Units"].items() if value != source_values[key]}
        except CatalogImportError:
            differences = {"projection": "Current source has unknown required fields; original installation values remain unchanged."}
        entry["legacyNotes"] = {"baseline": "6990010", "policy": "Preserve the original 12 UUIDs, names, categories, units, nutrients including null fibre, and source strings. Raw source cells remain independent evidence, not a claim that legacy published values equal a fresh projection.", "differences": differences}
    return entry


def build(workbook_path, curation):
    source_hash = hashlib.sha256(Path(workbook_path).read_bytes()).hexdigest()
    if source_hash != curation["source"]["sha256"]:
        raise CatalogImportError("source workbook SHA-256 differs from frozen release")
    validate_curation(curation["entries"])
    sheets, columns = read_workbook(workbook_path)
    records, duplicate_rows, row_count = source_records(sheets, columns)
    entries = []
    for review in curation["entries"]:
        if review["code"] not in records:
            raise CatalogImportError("missing or quarantined source code: " + review["code"])
        entries.append(make_entry(review, records[review["code"]]))
    if len(entries) < 300 or len({x["food"]["id"] for x in entries}) != len(entries):
        raise CatalogImportError("at least 300 distinct food IDs required")
    catalog = {"version": VERSION, "ruleVersion": RULE_VERSION, "source": curation["source"], "entries": entries}
    encoded = json_bytes(catalog)
    unavailable = Counter()
    for record in records.values():
        for field in list(REQUIRED.values()) + ["NA"]:
            if record["raw"][field].strip() in ("N", ""):
                unavailable[field] += 1
    manifest = {"catalogVersion": VERSION, "ruleVersion": RULE_VERSION, "source": curation["source"],
                "curationVersion": curation["curationVersion"], "curationSHA256": hashlib.sha256(json_bytes(curation)).hexdigest(),
                "catalogSHA256": hashlib.sha256(encoded).hexdigest(), "totalEntries": len(entries),
                "legacyEntries": sum(x["legacySeed"] for x in entries), "categories": dict(Counter(x["food"]["category"] for x in entries)),
                "sourceDataRows": row_count, "uniqueSourceCodes": len(records) + len({x["code"] for x in duplicate_rows}),
                "quarantinedSourceRows": duplicate_rows, "sourceRequiredUnknownCounts": dict(unavailable),
                "selectedAOACUnknown": sum(x["food"]["nutrientsPer100Units"]["fibreGrams"] is None for x in entries),
                "selectedRawCellStates": dict(Counter("trace" if value == "Tr" else "unknownN" if value == "N" else "blank" if value == "" else "numeric" for x in entries for value in x["rawNutrients"].values())),
                "curationExclusions": curation.get("excludedCandidates", []),
                "sourceColumns": columns, "identityPolicy": {"new": "UUIDv5 / NAMESPACE_URL / GOV publication URL + '#2021:' + food code", "legacy": LEGACY_IDS},
                "review": curation["review"], "reproduction": "python3 scripts/import_cofid.py /path/to/official-2021.xlsx --check"}
    return catalog, manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("workbook", type=Path)
    parser.add_argument("--check", action="store_true", help="compare regenerated bytes; do not write")
    args = parser.parse_args()
    try:
        curation = json.loads(CURATION.read_text(encoding="utf-8"))
        catalog, manifest = build(args.workbook, curation)
        for path, value in [(CATALOG, catalog), (MANIFEST, manifest)]:
            expected = json_bytes(value)
            if args.check:
                if not path.exists() or path.read_bytes() != expected:
                    raise CatalogImportError("generated file differs: " + str(path.relative_to(ROOT)))
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(expected)
        print(json.dumps({"catalogVersion": VERSION, "entries": len(catalog["entries"]), "legacy": manifest["legacyEntries"], "catalogSHA256": manifest["catalogSHA256"], "mode": "checked" if args.check else "generated"}, ensure_ascii=False))
    except (CatalogImportError, OSError, KeyError, zipfile.BadZipFile) as error:
        print("CoFID import failed: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
