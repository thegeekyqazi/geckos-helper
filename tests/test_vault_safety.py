import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from geckos_helper.desktop import obsidian, projects


class VaultSafetyTests(unittest.TestCase):
    def test_adoption_rejects_escape_before_writing(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            vault = root / 'vault'
            vault.mkdir()
            outside = root / 'outside.md'
            outside.write_text('# Untouched\n')
            (vault / 'escape.md').symlink_to(outside)
            with patch.object(projects, 'vault', return_value=vault), patch.object(obsidian, 'vault', return_value=vault):
                for name in ('../outside.md', str(outside), 'escape.md'):
                    with self.subTest(name=name), self.assertRaises(ValueError):
                        projects.adopt(name)
                self.assertEqual(outside.read_text(), '# Untouched\n')

    def test_in_vault_adoption_and_invalid_status(self):
        with tempfile.TemporaryDirectory() as td:
            vault = Path(td)
            note = vault / 'Fixture.md'
            note.write_text('# Fixture\n')
            with patch.object(projects, 'vault', return_value=vault), patch.object(obsidian, 'vault', return_value=vault), patch.object(projects, 'rebuild_hub'):
                with self.assertRaises(ValueError):
                    projects.adopt('Fixture.md', status='invalid')
                self.assertEqual(note.read_text(), '# Fixture\n')
                self.assertEqual(projects.adopt('Fixture.md')['status'], 'active')
