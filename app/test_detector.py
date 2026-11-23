"""Automated tests for the phishing detector."""

import unittest

from detector import analyze, check_attachments, check_links, check_sender


class DetectorTests(unittest.TestCase):
    """Each test checks one rule or one full verdict."""

    def test_ip_link_is_strong_sign(self):
        findings = check_links("Go to http://10.0.0.1/login")
        self.assertEqual(findings[0][2], 3)

    def test_lookalike_sender_is_flagged(self):
        self.assertEqual(len(check_sender("PayPal <service@paypa1.com>")), 1)

    def test_real_subdomain_is_not_flagged(self):
        self.assertEqual(check_sender("Google <no-reply@mail.google.com>"), [])

    def test_double_extension_gets_two_findings(self):
        self.assertEqual(len(check_attachments(["invoice.pdf.exe"])), 2)

    def test_sample_verdicts(self):
        expected = {
            "phishing1.txt": "phishing",
            "attachment1.txt": "phishing",
            "suspicious1.txt": "suspicious",
            "safe1.txt": "safe",
        }
        for filename, verdict in expected.items():
            with self.subTest(sample=filename):
                with open(f"samples/{filename}", encoding="utf-8") as f:
                    self.assertEqual(analyze(f.read())["verdict"], verdict)

    def test_history_adds_three_points(self):
        text = "From: a@b.com\nSubject: Hi\n\nHello"
        self.assertEqual(analyze(text, flagged_before=True)["score"], 3)


if __name__ == "__main__":
    unittest.main()
