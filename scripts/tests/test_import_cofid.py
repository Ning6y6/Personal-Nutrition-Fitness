"""Independent standard-library checks; no network, SwiftData or private records."""
import copy
from decimal import Decimal
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile

MODULE_PATH = Path(__file__).resolve().parents[1] / "import_cofid.py"
spec = importlib.util.spec_from_file_location("import_cofid", MODULE_PATH)
cofid = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cofid)


def complete_raw():
    return {"KCALS": "120", "KJ": "500", "PROT": "3", "FAT": "2", "SATFOD": "0.5",
            "CHO": "23", "TOTSUG": "1.05", "NA": "400", "AOACFIB": "2", "ENGFIB": "8"}


def column_name(index):
    text = ""
    while index:
        index, remainder = divmod(index - 1, 26)
        text = chr(65 + remainder) + text
    return text


def fixture_workbook(path, *, wrong_unit=None, wrong_code=None):
    ns = cofid.NS["m"]
    content = {}
    for index, name in enumerate(["1.1 Notes", "1.3 Proximates", "1.4 Inorganics", "1.5 Vitamins"], 1):
        sheet = ET.Element("{" + ns + "}worksheet")
        data = ET.SubElement(sheet, "{" + ns + "}sheetData")
        rows = {}
        if name == "1.1 Notes":
            rows[4] = {"A": "except alcoholic beverages: per 100ml; some fatty acids tabs are per 100g Fatty Acid"}
        else:
            rows = {1: {}, 2: {}, 4: {"A": "11-861", "B": "Rice, white, long grain, raw", "D": "AC"}}
            fields = [(code, field) for code, field in cofid.FIELDS.items() if field[0] == name]
            for number, (code, (_, unit, _, _, _)) in enumerate(fields, 8):
                col = column_name(number)
                rows[1][col] = code + " (" + ("g" if wrong_unit == code else unit) + ")"
                rows[2][col] = "SATFAC" if wrong_code == code else code
                rows[4][col] = complete_raw().get(code, "0")
        for number, cells in rows.items():
            row = ET.SubElement(data, "{" + ns + "}row", r=str(number))
            for col, value in cells.items():
                # The fixture uses shared strings just like the actual source workbook.
                cell = ET.SubElement(row, "{" + ns + "}c", r=col + str(number), t="s")
                ET.SubElement(cell, "{" + ns + "}v").text = value
        content[name] = sheet
    strings = []
    for sheet in content.values():
        for value in sheet.findall(".//m:v", cofid.NS):
            raw = value.text
            if raw not in strings:
                strings.append(raw)
            value.text = str(strings.index(raw))
    shared = ET.Element("{" + ns + "}sst")
    for raw in strings:
        item = ET.SubElement(shared, "{" + ns + "}si")
        ET.SubElement(item, "{" + ns + "}t").text = raw
    workbook = ET.Element("{" + ns + "}workbook")
    sheets = ET.SubElement(workbook, "{" + ns + "}sheets")
    rels = ET.Element("Relationships")
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("xl/sharedStrings.xml", ET.tostring(shared))
        for index, (name, sheet) in enumerate(content.items(), 1):
            ET.SubElement(sheets, "{" + ns + "}sheet", name=name, attrib={"{" + cofid.REL_NS + "}id": "rId" + str(index)})
            ET.SubElement(rels, "Relationship", Id="rId" + str(index), Target="worksheets/sheet" + str(index) + ".xml")
            archive.writestr("xl/worksheets/sheet" + str(index) + ".xml", ET.tostring(sheet))
        archive.writestr("xl/workbook.xml", ET.tostring(workbook))
        archive.writestr("xl/_rels/workbook.xml.rels", ET.tostring(rels))


class ScalarTests(unittest.TestCase):
    def test_zero_and_trace_are_calculation_zero_but_raw_tokens_differ(self):
        self.assertEqual(cofid.scalar("0"), Decimal(0))
        self.assertEqual(cofid.scalar("Tr"), Decimal(0))
        raw = complete_raw()
        raw["TOTSUG"] = "Tr"
        self.assertEqual(cofid.nutrients(raw, "per100gFood")["sugarGrams"], 0)
        self.assertEqual(raw["TOTSUG"], "Tr")

    def test_unknown_n_and_blank_are_not_numeric_zero(self):
        for raw in ["N", "", " "]:
            with self.subTest(raw=raw):
                self.assertIsNone(cofid.scalar(raw, required=False))
                with self.assertRaises(cofid.CatalogImportError):
                    cofid.scalar(raw)

    def test_invalid_and_negative_and_nonfinite_fail(self):
        for raw in ["-1", "NaN", "Infinity", "-Infinity", "1mg", "trace", "1,5"]:
            with self.subTest(raw=raw), self.assertRaises(cofid.CatalogImportError):
                cofid.scalar(raw)

    def test_every_required_unknown_blocks_publication(self):
        for code in list(cofid.REQUIRED.values()) + ["NA"]:
            for unknown in ["N", ""]:
                raw = complete_raw()
                raw[code] = unknown
                with self.subTest(code=code, unknown=unknown), self.assertRaises(cofid.CatalogImportError):
                    cofid.nutrients(raw, "per100gFood")


class MappingTests(unittest.TestCase):
    def test_sodium_400_mg_is_salt_one_gram(self):
        self.assertEqual(cofid.nutrients(complete_raw(), "per100gFood")["saltGrams"], 1)

    def test_kcal_comes_from_kcals_and_not_kilojoules_or_macro_recalculation(self):
        values = cofid.nutrients(complete_raw(), "per100gFood")
        self.assertEqual(values["energyKcal"], 120)
        self.assertNotEqual(values["energyKcal"], 500)
        self.assertNotEqual(values["energyKcal"], 4 * 3 + 9 * 2 + 4 * 23)

    def test_cho_and_total_sugar_keep_monosaccharide_equivalents(self):
        values = cofid.nutrients(complete_raw(), "per100gFood")
        self.assertEqual(values["carbohydrateGrams"], 23)
        self.assertEqual(values["sugarGrams"], 1.05)

    def test_missing_aoac_does_not_fall_back_to_nsp(self):
        for missing in ["N", ""]:
            raw = complete_raw()
            raw["AOACFIB"] = missing
            self.assertIsNone(cofid.nutrients(raw, "per100gFood")["fibreGrams"])
            self.assertEqual(raw["ENGFIB"], "8")

    def test_nonfood_mass_volume_and_serving_bases_fail(self):
        for basis in ["per100gFattyAcids", "per100ml", "perServing", "g", ""]:
            with self.subTest(basis=basis), self.assertRaises(cofid.CatalogImportError):
                cofid.nutrients(complete_raw(), basis)

    def test_source_units_and_codes_are_validated_independently(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "fixture.xlsx"
            fixture_workbook(path)
            sheets, columns = cofid.read_workbook(path)
            self.assertEqual(columns["NA"]["unit"], "mg")
            self.assertEqual(columns["RET"]["unit"], "µg")
            self.assertEqual(columns["SATFOD"]["basis"], "per100gFood")
            records, duplicates, count = cofid.source_records(sheets, columns)
            self.assertEqual(records["11-861"]["raw"]["NA"], "400")
            self.assertEqual((duplicates, count), ([], 1))
            fixture_workbook(path, wrong_unit="NA")
            with self.assertRaises(cofid.CatalogImportError):
                cofid.read_workbook(path)
            fixture_workbook(path, wrong_code="SATFOD")
            with self.assertRaises(cofid.CatalogImportError):
                cofid.read_workbook(path)

    def test_duplicate_source_codes_are_quarantined_together(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "fixture.xlsx"
            fixture_workbook(path)
            sheets, columns = cofid.read_workbook(path)
            for name, rows in sheets.items():
                if name != "1.1 Notes":
                    rows[5] = dict(rows[4], B="Different food with the same code")
            records, duplicates, count = cofid.source_records(sheets, columns)
            self.assertEqual(records, {})
            self.assertEqual(count, 2)
            self.assertEqual([x["row"] for x in duplicates], [4, 5])

    def test_cross_sheet_name_mismatch_fails_instead_of_joining_by_name(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "fixture.xlsx"
            fixture_workbook(path)
            sheets, columns = cofid.read_workbook(path)
            sheets["1.4 Inorganics"][4]["B"] = "Another food"
            with self.assertRaises(cofid.CatalogImportError):
                cofid.source_records(sheets, columns)


class FrozenCurationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.curation = json.loads(cofid.CURATION.read_text(encoding="utf-8"))
        cls.catalog = json.loads(cofid.CATALOG.read_text(encoding="utf-8"))

    def test_real_food_count_and_legacy_snapshots(self):
        rows = self.curation["entries"]
        cofid.validate_curation(rows)
        self.assertEqual(len(rows), 357)
        self.assertEqual(len({x["code"] for x in rows}), 357)
        self.assertEqual(sum("legacyFood" in x for x in rows), 12)
        self.assertNotIn("13-669", {x["code"] for x in rows})
        for review, entry in zip(rows, self.catalog["entries"]):
            if "legacyFood" in review:
                self.assertEqual(review["legacyFood"], entry["food"])
        self.assertEqual(sum(x["food"]["nutrientsPer100Units"]["fibreGrams"] is None for x in self.catalog["entries"][:12]), 6)

    def test_legacy_nil_source_or_values_cannot_be_changed(self):
        for field, value in [("fibreGrams", 0), ("energyKcal", 999)]:
            rows = copy.deepcopy(self.curation["entries"])
            target = next(x for x in rows if x["code"] == "13-318")
            target["legacyFood"]["nutrientsPer100Units"][field] = value
            with self.subTest(field=field), self.assertRaises(cofid.CatalogImportError):
                cofid.validate_curation(rows)
        rows = copy.deepcopy(self.curation["entries"])
        rows[0]["legacyFood"]["source"] += " changed"
        with self.assertRaises(cofid.CatalogImportError):
            cofid.validate_curation(rows)

    def test_duplicate_curation_and_invalid_pinyin_fail(self):
        rows = copy.deepcopy(self.curation["entries"])
        rows.append(rows[-1])
        with self.assertRaises(cofid.CatalogImportError):
            cofid.validate_curation(rows)
        for key in ["j xr", "JXR", "鸡胸肉", "", "123"]:
            rows = copy.deepcopy(self.curation["entries"])
            rows[-1]["pinyinInitials"] = [key]
            with self.subTest(key=key), self.assertRaises(cofid.CatalogImportError):
                cofid.validate_curation(rows)

    def test_confirmed_search_samples_preserve_food_identity_and_state(self):
        entries = {x["code"]: x for x in self.catalog["entries"]}
        self.assertIn("番茄", entries["13-517"]["aliases"])
        self.assertIn("jxr", entries["18-323"]["pinyinInitials"])
        self.assertIn("生米", entries["11-861"]["aliases"])
        self.assertEqual(entries["11-861"]["food"]["id"], "0a47a02c-713f-5816-977c-6467c0244e6a")
        self.assertEqual(entries["11-862"]["food"]["name"], "熟长粒白米饭（无盐）")
        self.assertNotEqual(entries["11-861"]["food"]["id"], entries["11-862"]["food"]["id"])
        self.assertNotIn("米饭", entries["11-861"]["aliases"])

    def test_retinol_re_aoac_trans_and_cholesterol_stay_separate(self):
        for entry in self.catalog["entries"]:
            raw = entry["rawNutrients"]
            for field in ["RET", "RETEQU", "CAREQU", "CHO", "TOTSUG", "AOACFIB", "ENGFIB", "FODTRANS", "MONOFOD", "POLYFOD", "CHOL"]:
                self.assertIn(field, raw)
                self.assertIsInstance(raw[field], str)
            self.assertNotIn("RAE", raw)
            self.assertEqual(entry["basis"], "per100gFood")
            if not entry["legacySeed"]:
                self.assertEqual(entry["food"]["nutrientsPer100Units"], cofid.nutrients(raw, entry["basis"]))


if __name__ == "__main__":
    unittest.main()
