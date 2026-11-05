"""Tests of report_xml.py's reading of a GenesisReport timeline.

The XML is the format the client's SaveAddonObject writes (fact 0x140185f30: <Document> with one
<N K="key"|F="n" T="t|n|s|b" V="value"> per entry, a boolean + or -). The expected times come from
the Unix seconds written in the XML: 1793837439 is 2026-11-05T00:10:39Z (date -u -r 1793837439).
"""

import contextlib
import io
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import report_xml  # noqa: E402

INSTALLED_AT = 1793837400

# Three entries: a poll in combat, the event that leaves combat, a poll after it; one Lua error.
TIMELINE_XML = """<?xml version="1.0" encoding="UTF-8"?>
<Document>
  <N K="bTimeline" T="b" V="+"/>
  <N K="bReported" T="b" V="+"/>
  <N K="nReportedAt" T="n" V="1793837445"/>
  <N K="nInstalledAt" T="n" V="1793837400"/>
  <N K="nTimelineMinutes" T="n" V="20"/>
  <N K="bTimelineFinished" T="b" V="-"/>
  <N K="tLuaErrorEvents" T="t">
    <N F="1" T="t">
      <N K="strAddon" T="s" V="Some&amp;Addon"/>
      <N K="strError" T="s" V="attempt to index nil"/>
    </N>
  </N>
  <N K="arTimeline" T="t">
    <N F="1" T="t">
      <N K="nTime" T="n" V="1793837439"/>
      <N K="nGameTime" T="n" V="123.5"/>
      <N K="strSource" T="s" V="poll"/>
      <N K="bPlayerUnit" T="b" V="+"/>
      <N K="bInCombat" T="b" V="+"/>
      <N K="nResource" T="n" V="0"/>
      <N K="nMaxResource" T="n" V="4"/>
    </N>
    <N F="2" T="t">
      <N K="nTime" T="n" V="1793837439"/>
      <N K="nGameTime" T="n" V="123.75"/>
      <N K="strSource" T="s" V="event"/>
      <N K="bEventInCombat" T="b" V="-"/>
      <N K="bPlayerUnit" T="b" V="+"/>
      <N K="bInCombat" T="b" V="-"/>
      <N K="nResource" T="n" V="0"/>
      <N K="nMaxResource" T="n" V="4"/>
    </N>
    <N F="3" T="t">
      <N K="nTime" T="n" V="1793837440"/>
      <N K="strSource" T="s" V="poll"/>
      <N K="bPlayerUnit" T="b" V="-"/>
    </N>
  </N>
</Document>
"""


def timeline_report():
    return report_xml.convert(TIMELINE_XML)


def run_main(arguments):
    """The exit status, standard output and standard error of report_xml.main."""
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        status = report_xml.main(["report_xml.py"] + arguments)
    return status, out.getvalue(), err.getvalue()


class TimelineConversionTest(unittest.TestCase):
    def test_the_entries_become_a_list_in_their_key_order(self):
        report = timeline_report()
        self.assertEqual([entry["nTime"] for entry in report["arTimeline"]], [1793837439, 1793837439, 1793837440])
        self.assertEqual(report["arTimeline"][0]["nGameTime"], 123.5)
        self.assertIs(report["arTimeline"][0]["bInCombat"], True)
        self.assertIs(report["arTimeline"][1]["bEventInCombat"], False)

    def test_a_timeline_report_from_this_install_is_accepted(self):
        report_xml.check_timeline(timeline_report(), INSTALLED_AT)

    def test_each_entry_prints_as_one_line_each_lua_error_after_them_and_the_end_line_last(self):
        self.assertEqual(
            report_xml.timeline_lines(timeline_report()),
            [
                "2026-11-05T00:10:39Z game 123.5 poll combat true resource 0/4",
                "2026-11-05T00:10:39Z game 123.75 event out combat false resource 0/4",
                "2026-11-05T00:10:40Z game - poll combat - resource -/-",
                "lua error Some&Addon: attempt to index nil",
                "end saved 2026-11-05T00:10:45Z last entry 2026-11-05T00:10:40Z finished false",
            ],
        )

    def test_a_timeline_whose_minutes_ran_out_says_it_finished(self):
        report = timeline_report()
        report["bTimelineFinished"] = True
        self.assertEqual(
            report_xml.timeline_lines(report)[-1],
            "end saved 2026-11-05T00:10:45Z last entry 2026-11-05T00:10:40Z finished true",
        )


class TimelineRefusalTest(unittest.TestCase):
    def refused(self, report, installed_at=INSTALLED_AT):
        with self.assertRaises(ValueError) as caught:
            report_xml.check_timeline(report, installed_at)
        return str(caught.exception)

    def test_a_report_from_another_install_is_refused(self):
        self.assertIn("earlier session", self.refused(timeline_report(), INSTALLED_AT + 1))

    def test_an_entry_before_the_install_is_refused(self):
        report = timeline_report()
        report["arTimeline"][0]["nTime"] = INSTALLED_AT - 1
        self.assertIn("entry 1", self.refused(report))

    def test_an_entry_that_goes_back_is_refused(self):
        report = timeline_report()
        report["arTimeline"][2]["nTime"] = 1793837438
        self.assertIn("entry 3", self.refused(report))

    def test_an_entry_after_the_save_is_refused(self):
        report = timeline_report()
        report["nReportedAt"] = 1793837439
        self.assertIn("entry 3", self.refused(report))

    def test_a_one_shot_report_is_refused(self):
        self.assertIn("bTimeline", self.refused({"bReported": True, "nReportedAt": 1793837439}))

    def test_a_timeline_with_no_entries_is_refused(self):
        report = timeline_report()
        report["bReported"] = False
        report["arTimeline"] = {}
        self.assertIn("no entries", self.refused(report))


class TimelineCommandTest(unittest.TestCase):
    def write_report(self, report):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        path = os.path.join(folder.name, "report.json")
        with open(path, "w", encoding="utf-8") as saved:
            json.dump(report, saved)
        return path

    def test_the_command_prints_the_lines_of_an_accepted_timeline(self):
        path = self.write_report(timeline_report())
        status, out, _ = run_main(["--timeline", path, str(INSTALLED_AT)])
        self.assertEqual(status, 0)
        self.assertEqual(out.splitlines()[0], "2026-11-05T00:10:39Z game 123.5 poll combat true resource 0/4")
        self.assertEqual(len(out.splitlines()), 5)
        self.assertTrue(out.splitlines()[-1].startswith("end saved "))

    def test_the_command_prints_nothing_and_exits_1_on_a_refused_timeline(self):
        path = self.write_report(timeline_report())
        status, out, err = run_main(["--timeline", path, str(INSTALLED_AT + 1)])
        self.assertEqual((status, out), (1, ""))
        self.assertIn("earlier session", err)

    def test_the_xml_form_still_prints_the_json_of_a_one_shot_report(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        path = os.path.join(folder.name, "GenesisReport_0_Acct.xml")
        with open(path, "w", encoding="utf-8") as saved:
            saved.write('<?xml version="1.0" encoding="UTF-8"?>\n<Document>'
                        '<N K="bReported" T="b" V="+"/><N K="nReportedAt" T="n" V="1793837439"/></Document>')
        status, out, _ = run_main([path])
        self.assertEqual(status, 0)
        self.assertEqual(json.loads(out), {"bReported": True, "nReportedAt": 1793837439})


if __name__ == "__main__":
    unittest.main()
