# SPDX-License-Identifier: GPL-3.0-only
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

HELPER = Path(__file__).resolve().parents[1] / 'search-files.py'

class FileSearchTest(unittest.TestCase):
    def test_special_filenames_and_request_identity(self):
        with tempfile.TemporaryDirectory() as folder:
            names = ['Rechnung 2026.pdf', 'Rechnung\nZwei.txt', "Rechnung 'quote'.txt"]
            for name in names:
                (Path(folder) / name).touch()
            output = subprocess.check_output(['python3', str(HELPER), '42', 'rechnung', folder], text=True)
            result = json.loads(output)
            self.assertEqual(result['token'], 42)
            self.assertEqual(result['error'], '')
            self.assertEqual({Path(p).name for p in result['paths']}, set(names))

if __name__ == '__main__':
    unittest.main()
