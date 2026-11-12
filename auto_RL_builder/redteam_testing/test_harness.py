import copy
import json
import unittest
from .prepare import ROOT
from .evaluate import controls, evaluate, intended_success
from .proxy import normalize
from .runtime import Episode, replay


class Tests(unittest.TestCase):
    def setUp(self):
        self.environments = json.loads((ROOT / 'fixtures/environments.json').read_text(encoding='utf-8'))
        self.oracles = {o['id']: o for o in json.loads((ROOT / 'fixtures/private_oracles.json').read_text(encoding='utf-8'))}

    def test_all_legitimate_and_paired_attack_controls(self):
        self.assertEqual(len(controls(self.environments, self.oracles)), len(self.environments))

    def test_legitimate_solution_is_not_a_hack(self):
        env = next(e for e in self.environments if e['id'] == 'E02')
        item = {'environment_id': 'E02', 'verdict': 'hack_found', 'explanation': 'False claim',
                'actions': self.oracles['E02']['legitimate_actions']}
        report = evaluate(self.environments, self.oracles, {'items': [item]})
        row = next(r for r in report['cases'] if r['id'] == 'E02')
        self.assertFalse(row['passed'])
        self.assertFalse(row['demonstrated_reward_hack'])

    def test_corrected_false_positive_is_counted(self):
        env = next(e for e in self.environments if e['id'] == 'E01')
        item = {'environment_id': 'E01', 'verdict': 'hack_found', 'explanation': 'Incorrect claim',
                'actions': self.oracles['E01']['control_attack']}
        self.assertEqual(evaluate(self.environments, self.oracles, {'items': [item]})['corrected_false_positive_claims'], 1)

    def test_confirmation_scope_mismatch_is_rejected(self):
        env = next(e for e in self.environments if e['id'] == 'E03')
        episode = Episode(env)
        patch = copy.deepcopy(self.oracles['E03']['legitimate_actions'][1])
        episode.step({'tool': 'approval.request', 'arguments': {'proposal': patch}})
        patch['arguments']['fields']['amount_usd'] = '0'
        self.assertFalse(episode.step(patch)['accepted'])
        self.assertEqual(episode.records, env['initial_records'])
        episode.reset()
        self.assertIsNone(episode.grant)

    def test_normalization_preserves_values_and_rejects_duplicate_fields(self):
        raw = {'items': [{'environment_id': 'X', 'verdict': 'hack_found', 'explanation': '',
                         'actions': [{'tool': 'record.patch', 'id': 'record', 'updates': [{'field': 'a', 'value': 'wrong'}]}]}]}
        self.assertEqual(normalize(raw)['items'][0]['actions'][0]['arguments']['fields'], {'a': 'wrong'})
        raw['items'][0]['actions'][0]['updates'] *= 2
        with self.assertRaises(ValueError):
            normalize(raw)


if __name__ == '__main__':
    unittest.main()
