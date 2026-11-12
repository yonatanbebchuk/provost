import copy
import json
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch

from scripts import reward_hack_server as server
from scripts.prepare_diff_studio_data import agency_attack, enrich_story_fields, matt_redteam_attack


class StoryAPITests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / 'registry.json'
        attacks = [enrich_story_fields(agency_attack()), enrich_story_fields(matt_redteam_attack('medrec'))]
        custom = copy.deepcopy(attacks[0]); custom['id'] = 'custom'; custom.pop('story')
        self.path.write_text(json.dumps({'attacks': attacks + [custom]}))
        self.path_patch = patch.object(server, 'REGISTRY_PATH', self.path)
        self.path_patch.start()
        self.http = ThreadingHTTPServer(('127.0.0.1', 0), server.Handler)
        self.thread = threading.Thread(target=self.http.serve_forever, daemon=True)
        self.thread.start()
        self.base = f'http://127.0.0.1:{self.http.server_port}'

    def tearDown(self):
        self.http.shutdown(); self.http.server_close(); self.thread.join()
        self.path_patch.stop(); self.temp.cleanup()

    def request(self, path, body=None):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self.base + path, data=data, headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(req) as response:
            return json.load(response)

    def test_environment_and_control_contract(self):
        env = self.request('/api/attacks/matt_medrec')
        self.assertEqual(env['story']['rewardSource']['language'], 'python')
        c = self.request('/api/story/matt_medrec/control', {})
        self.assertEqual(c['evidence']['provenance']['generation'], 'Authored control')
        replay = self.request('/api/story/matt_medrec/replay', {'candidateDigest': c['evidence']['candidateDigest'], 'patchId': c['evidence']['patchId']})
        self.assertEqual(replay['replay']['candidateDigest'], c['evidence']['candidateDigest'])
        self.assertEqual(replay['score'], 0.0)

    def test_bad_identity_is_rejected_not_displayed_as_fixed(self):
        with self.assertRaises(urllib.error.HTTPError) as error:
            self.request('/api/story/matt_medrec/replay', {'candidateDigest': 'changed'})
        self.assertEqual(error.exception.code, 400)
        self.assertIn('changed', json.load(error.exception)['error'])

    def test_custom_source_unavailable_and_replay_disabled(self):
        a = self.request('/api/attacks/custom')
        self.assertFalse(a['story']['canReplay'])
        c = self.request('/api/story/custom/control', {})
        self.assertEqual(c['evidence']['intentStatus'], 'unknown')
        with self.assertRaises(urllib.error.HTTPError) as error:
            self.request('/api/story/custom/replay', {})
        self.assertEqual(error.exception.code, 400)

    def test_existing_registry_custom_entries_are_preserved_on_refresh(self):
        demo = {'attacks': [enrich_story_fields(matt_redteam_attack('medrec'))]}
        path = Path(self.temp.name) / 'demo.json'; path.write_text(json.dumps(demo))
        with patch.object(server, 'DATA_PATH', path), patch.object(server.subprocess, 'run'):
            result = server.ensure_data()
        self.assertIn('custom', [a['id'] for a in result['attacks']])


if __name__ == '__main__':
    unittest.main()
