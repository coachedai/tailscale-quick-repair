#!/usr/bin/env python3
"""Offline source/wiring checks. Not a replacement for native Windows acceptance.

Requires PyYAML for workflow parsing. No network, installation or Git writes.
"""
from pathlib import Path
import importlib.util
import json
import re
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[1]
AUDIT_PATH = ROOT / 'release/audit-git-history.py'
spec = importlib.util.spec_from_file_location('tqr_history_audit', AUDIT_PATH)
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)

def text(relative):
    return (ROOT / relative).read_text(encoding='utf-8-sig')

class DevelopmentGuardrails(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow = yaml.safe_load(text('.github/workflows/auto-repair-development.yml'))
        cls.jobs = cls.workflow['jobs']

    def test_publisher_needs_history_and_both_native_jobs(self):
        pub = self.jobs['preview-publish']
        self.assertEqual(set(pub['needs']), {'verify', 'released-upgrade', 'history-privacy'})
        self.assertIn("needs.history-privacy.result == 'success'", pub['if'])
        self.assertIn("needs.released-upgrade.result == 'success'", pub['if'])
        self.assertIn("needs.verify.outputs.preview_publish == 'true'", pub['if'])

    def test_history_job_exact_source_and_read_only(self):
        job = self.jobs['history-privacy']
        self.assertEqual(job['permissions'], {'contents':'read'})
        checkout = job['steps'][0]['with']
        self.assertEqual(checkout['ref'], '${{ github.sha }}')
        self.assertEqual(checkout['fetch-depth'], 0)
        self.assertFalse(checkout['persist-credentials'])
        self.assertFalse(checkout['submodules'])
        commands = '\n'.join(x.get('run','') for x in job['steps'])
        self.assertIn('test "$GITHUB_REPOSITORY" = "coachedai/tailscale-quick-repair"', commands)
        self.assertIn('test-git-history-audit.py', commands)
        self.assertIn('audit-git-history.py --result', commands)
        self.assertNotIn('git push', commands)
        for family in ('heads', 'tags', 'pull'):
            self.assertIn('refs/'+family+'/', commands)

    def test_source_parse_gate_precedes_expensive_tests(self):
        steps = self.jobs['verify']['steps']
        names = [x.get('name','') for x in steps]
        syntax = next(i for i,x in enumerate(steps) if 'test-source-syntax.ps1' in x.get('run',''))
        self.assertLess(syntax, names.index('Build both existing delivery paths'))
        self.assertLess(syntax, names.index('Real installed Windows service and full recurrence gates'))

    def test_upgrade_source_parsed_before_mutation(self):
        steps = self.jobs['released-upgrade']['steps']
        syntax = next(i for i,x in enumerate(steps) if 'test-source-syntax.ps1' in x.get('run',''))
        bridge = next(i for i,x in enumerate(steps) if 'test-published-rc1-bridge.ps1' in x.get('run',''))
        self.assertLess(syntax, bridge)

    def test_rejected_source_is_not_archived(self):
        steps = self.jobs['verify']['steps']
        preflight = next(x for x in steps if x.get('id')=='source_privacy')
        self.assertIn('privacy-scan.ps1', preflight['run'])
        archive = next(x for x in steps if x.get('name')=='Preserve exact source snapshot')
        self.assertEqual(archive['if'], "always() && steps.source_privacy.outcome == 'success'")

    def test_upgrade_script_not_duplicated(self):
        s = text('release/test-preview-upgrade.ps1')
        functions = re.findall(r'^function ([A-Za-z-]+)\b', s, re.M)
        self.assertEqual(len(functions), len(set(functions)))
        self.assertEqual(s.count('param(\n'), 1)
        self.assertEqual(s.count('$match=[regex]::Match('), 1)
        self.assertIn(r"$match=[regex]::Match($candidateVersion,'\A3\.0\.0-rc\.([1-9][0-9]*)\z')", s)
        self.assertIn('$candidateCode -ne (30001000+[int64]$match.Groups[1].Value)', s)
        self.assertIn('SHA-256', s)
        self.assertIn('ValidatePackageChannelBinding', s)
        self.assertIn('ValidateProtectedUpdateMarker', s)
        self.assertIn('Acknowledge-ProtectedRestart', s)

    def test_native_parser_gate_does_not_execute_sources(self):
        s = text('release/test-source-syntax.ps1')
        self.assertIn('[Management.Automation.Language.Parser]::ParseInput', s)
        self.assertIn('Text.UTF8Encoding($false,$true)', s)
        self.assertIn('fileSha256=$fileId', s)
        for forbidden in ('Invoke-Expression', '[scriptblock]::Create', '& $file', '. $file'):
            self.assertNotIn(forbidden, s)

    def test_privacy_messages_do_not_echo_findings(self):
        s = text('release/privacy-scan.ps1')
        self.assertIn('file-sha256=$pathId', s)
        self.assertNotIn('$List.Add("$Path', s)
        self.assertNotIn('Email address detected: $email', s)
        self.assertNotIn('Literal IPv4 address detected: $value', s)

    def test_passive_ui_guards_before_collection_and_presentation(self):
        s = text('release/add-passive-startup-health.ps1')
        for name in ('Invoke-PassiveStartupHealth','Apply-PassiveStartupPresentation','Update-PassiveTrayStatus'):
            start = s.index('    function '+name+' {')
            stop = s.find('\n    function ', start+1)
            block = s[start:stop if stop>=0 else len(s)]
            self.assertIn('Test-PassiveStartupPresentationAllowed', block)
        invoke = s[s.index('    function Invoke-PassiveStartupHealth {'):]
        self.assertLess(invoke.index('Test-PassiveStartupPresentationAllowed'), invoke.index('$machine.Observe()'))
        for flag in ('TqrUiShutdownRequested','repairActive','updateDownloadActive','pendingProtectedUpdateStarted','lastData'):
            self.assertIn(flag, s[s.index('function Test-PassiveStartupPresentationAllowed'):s.index('function Get-PassiveStartupConfigState')])

    def test_publication_switch_still_off(self):
        self.assertFalse(json.loads(text('release/preview-publish.json'))['publish'])
        self.assertFalse(json.loads(text('release/publish.json'))['publish'])
        self.assertEqual(json.loads(text('version.json'))['version'], '3.0.0-rc.3')

    def test_changed_source_contains_no_recognized_private_patterns(self):
        checked = [
            'release/audit-git-history.py', 'release/privacy-scan.ps1',
            'release/test-git-history-audit.py', 'release/test-development-guardrails.py',
            'release/test-source-syntax.ps1', 'release/test-preview-upgrade.ps1',
            'release/test-preview-pipeline.ps1', 'release/add-passive-startup-health.ps1',
            'release/test-passive-startup-health.ps1',
            '.github/workflows/history-privacy-audit.yml',
            '.github/workflows/auto-repair-development.yml',
        ]
        findings=[]
        for relative in checked:
            audit.scan_text(text(relative), lambda *args: findings.append(args), 'synthetic-object-id', 'source')
        self.assertEqual(findings, [])

if __name__ == '__main__':
    unittest.main(verbosity=2)
