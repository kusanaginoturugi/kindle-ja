"""kindle-ja-ocrd の段落の組み立てを、OCR の枠を手で作って確かめる（RapidOCR は要らない）。

python3 -m unittest discover -s tests
"""
import unittest
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path

path = Path(__file__).resolve().parent.parent / "kindle-ja-ocrd"
loader = SourceFileLoader("kindle_ja_ocrd", str(path))
ocrd = module_from_spec(spec_from_loader("kindle_ja_ocrd", loader))
loader.exec_module(ocrd)


def box(top, height=50, left=30, width=900):
    return [(left, top), (left + width, top), (left + width, top + height), (left, top + height)]


def page(rows):
    """(行の上端, 文字) の並びから、行ごとに 1 つの枠を作る。"""
    return [(box(top), text) for top, text in rows]


class ParagraphsTest(unittest.TestCase):
    def build(self, rows):
        return ocrd.paragraphs(ocrd.group_lines(page(rows)))

    def test_kindle_spacing(self):
        # Kindle：段落の中は 66、段落の間は 76。1 行だけの段落（話者名）も混ざる
        rows = [(0, "THE CAPTAIN"), (76, "(She looks at the console, and the lights"),
                (142, "grow dimmer.)"), (218, "I know every corridor of this place."),
                (294, "NAVIGATOR"), (370, "(Quietly.)"), (446, "Then we wait.")]
        self.assertEqual(self.build(rows), [
            "THE CAPTAIN", "(She looks at the console, and the lights grow dimmer.)",
            "I know every corridor of this place.", "NAVIGATOR", "(Quietly.)", "Then we wait."])

    def test_blank_line_between_paragraphs(self):
        # 段落の間に 1 行空いている本（行間 66、段落の間 132）
        rows = [(0, "Alice was beginning"), (66, "to get very tired."),
                (198, "So she was considering"), (264, "in her own mind.")]
        self.assertEqual(self.build(rows), [
            "Alice was beginning to get very tired.", "So she was considering in her own mind."])

    def test_only_single_line_paragraphs(self):
        # 1 行の段落だけが並ぶと、行間はどれも同じ。行の高さ（50）の 1.45 倍より広いので、全部切る
        rows = [(0, "ONE"), (78, "(Two.)"), (156, "Three."), (234, "FOUR")]
        self.assertEqual(self.build(rows), ["ONE", "(Two.)", "Three.", "FOUR"])

    def test_one_paragraph(self):
        # 段落が 1 つだけなら、行間はどれも狭いので切らない
        rows = [(0, "It was a long"), (66, "day, and the"), (132, "night was longer.")]
        self.assertEqual(self.build(rows), ["It was a long day, and the night was longer."])

    def test_hyphen_at_line_end(self):
        rows = [(0, "the reactor hums with a steady, regu-"), (66, "lar rhythm"), (132, "and a well-"),
                (198, "Known name.")]
        self.assertEqual(self.build(rows), ["the reactor hums with a steady, regular rhythm and a well- Known name."])

    def test_boxes_on_the_same_row_are_joined_left_to_right(self):
        items = [(box(2, 48, left=500, width=300), "of the line"), (box(0, 50, left=30, width=450), "The first half")]
        self.assertEqual(ocrd.group_lines(items), [(0, 50, "The first half of the line")])

    def test_empty(self):
        self.assertEqual(ocrd.paragraphs([]), [])


if __name__ == "__main__":
    unittest.main()
