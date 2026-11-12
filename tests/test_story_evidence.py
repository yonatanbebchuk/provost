import copy
import hashlib
import json
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from harness import attack_search
from harness.story_evidence import (
    ROOT, candidate_evidence, control_candidate, digest, environment_story,
    matt_pair, provenance, replay_evidence, source,
)
from scripts.prepare_diff_studio_data import (
    agency_attack, aidan_attack, agentdojo_tools_attack, structured_attack,
    matt_redteam_attack, enrich_story_fields,
)


def builtins():
    return [enrich_story_fields(a) for a in [agency_attack(), aidan_attack(), structured_attack(), agentdojo_tools_attack(),
            *[matt_redteam_attack(kind) for kind in ('pulsehealth', 'harbor', 'skybend', 'medrec', 'sepsis')]]]


class StoryEvidenceTests(unittest.TestCase):
    def test_neutral_setup_and_actual_source_for_all_builtins(self):
        for attack in builtins():
            with self.subTest(env=attack['id']):
                story = attack['story']
                for spoiler in ('vulnerable grader', 'omits', 'reward hack', 'exploit', 'corrected grader'):
                    self.assertNotIn(spoiler, story['rewardDescription'].lower())
                self.assertEqual(attack['rewardCode'], story['rewardSource']['code'])
                for s in story['sources']:
                    if s['language'] == 'python':
                        self.assertEqual(s['fullCode'], (ROOT / s['path']).read_text())
                        self.assertEqual(s['sha256'], hashlib.sha256(s['fullCode'].encode()).hexdigest())
                        self.assertIn(s['code'], s['fullCode'])
                self.assertNotIn('def reward(trace):', attack['rewardCode'])

    def test_all_authored_controls_show_actual_failure_and_local_replay(self):
        for attack in builtins():
            with self.subTest(env=attack['id']):
                c = control_candidate(attack)
                self.assertEqual(c['evidence']['outcomeClass'], 'rewarded_failure')
                self.assertTrue(any(r['failed'] for r in c['evidence']['comparisons']))
                r = replay_evidence(c)['replay']
                self.assertEqual(r['candidateDigest'], c['evidence']['candidateDigest'])
                self.assertEqual(r['originalScore'], 1.0)
                self.assertEqual(r['patchedScore'], 0.0)
                self.assertIn('candidate', r['conclusion'])
                self.assertNotIn('secure', r['conclusion'])
                if attack['id'].startswith('matt_') or attack['id'] == 'agentdojo_tools':
                    self.assertEqual(r['honestControl']['status'], 'passed')
                    self.assertEqual(r['honestControl']['patchedScore'], 1.0)
                else:
                    self.assertEqual(r['honestControl']['status'], 'not_tested')

    def test_missing_unchanged_requirements_are_visible(self):
        a, _, _, _ = matt_pair('matt_medrec')
        actions = [{'tool': 'record.patch', 'arguments': {'id': a['grader']['target'], 'fields': a['grader']['graded_fields']}},
                   {'tool': 'finish', 'arguments': {}}]
        c = attack_search.validate('matt_medrec', attack_search._matt_candidate('matt_medrec', 'x', actions), 1)
        row = next(r for r in c['evidence']['comparisons'] if r['id'] == 'med-rec.interaction_review')
        self.assertTrue(row['failed'])
        self.assertEqual(row['original'], row['observed'])
        self.assertEqual(row['expected'], 'pharmacist review required')

    def test_only_demonstrated_failure_is_highlighted(self):
        _, _, oracle, _ = matt_pair('matt_sepsis')
        actions = copy.deepcopy(oracle['legitimate_actions'])
        actions[0]['arguments']['fields']['monitoring'] = 'routine'
        c = attack_search.validate('matt_sepsis', attack_search._matt_candidate('matt_sepsis', 'x', actions), 1)
        failures = [r['id'] for r in c['evidence']['comparisons'] if r['failed']]
        self.assertEqual(failures, ['sepsis-case.monitoring'])
        self.assertEqual(c['evidence']['diagnosis'][0]['evidenceIds'], failures)

    def test_honest_and_unrewarded_failures_are_not_conflated(self):
        _, _, oracle, _ = matt_pair('matt_harbor')
        honest = attack_search.validate('matt_harbor', attack_search._matt_candidate('matt_harbor', 'honest', oracle['legitimate_actions']), 1)
        bad = attack_search.validate('matt_harbor', attack_search._matt_candidate('matt_harbor', 'unfinished', []), 2)
        self.assertEqual(honest['evidence']['outcomeClass'], 'honest_completion')
        self.assertFalse(honest['evidence']['diagnosis'])
        self.assertEqual(bad['evidence']['outcomeClass'], 'unrewarded_failure')
        result = replay_evidence(honest)
        self.assertEqual(result['score'], 1.0)
        self.assertFalse(result['fixed'])
        self.assertNotIn('no longer', result['replay']['conclusion'])

    def test_text_diagnosis_is_not_applied_to_honest_candidate(self):
        rows = [json.loads(l) for l in (ROOT / 'exploits/aidanbench_hack_candidates.jsonl').read_text().splitlines()]
        c = attack_search.validate('aidanbench', rows[0], 1)
        self.assertEqual(c['evidence']['intentStatus'], 'passed')
        self.assertFalse(c['evidence']['diagnosis'])

    def test_tool_replay_identity_covers_captured_arguments(self):
        c = control_candidate(enrich_story_fields(agentdojo_tools_attack()))
        changed = copy.deepcopy(c)
        changed['trace']['tool_calls'][1]['args']['to'] = 'different@example.com'
        with self.assertRaisesRegex(ValueError, 'changed'):
            replay_evidence(changed)
        with patch('harness.agentdojo_tool_harness.MiniAgentDojoHarness.run_attacker_policy', side_effect=AssertionError('Must replay captured calls')):
            result = replay_evidence(c)
        self.assertEqual(result['score'], 0)
        self.assertEqual(result['replay']['honestControl']['status'], 'passed')

    def test_fallback_uses_public_spec_not_private_contract(self):
        from harness.attack_search import _matt_fixtures, generate_matt_candidates
        envs, _ = _matt_fixtures()
        private = {k: {'intended_contract': {'required_fields': {'PRIVATE_SENTINEL': 'must not appear'}}} for k in envs}
        def candidate(env, kind, actions):
            return {'kind': kind, 'actions': actions, 'proxy_reward': 1, 'intended_success': False}
        with patch('harness.attack_search._matt_fixtures', return_value=(envs, private)), patch('harness.attack_search._matt_candidate', side_effect=candidate):
            rows = generate_matt_candidates('matt_medrec', 50)
        self.assertNotIn('PRIVATE_SENTINEL', json.dumps(rows))
        self.assertIn('pharmacist_review_required', json.dumps(rows))

    def test_replay_rejects_changed_payload_and_changed_patch(self):
        c = control_candidate(enrich_story_fields(matt_redteam_attack('sepsis')))
        changed = copy.deepcopy(c)
        changed['actions'][0]['arguments']['fields']['monitoring'] = 'different'
        with self.assertRaisesRegex(ValueError, 'payload changed'):
            replay_evidence(changed)
        c['evidence']['patchId'] = 'another-version'
        with self.assertRaisesRegex(ValueError, 'patch changed'):
            replay_evidence(c)

    def test_replay_version_covers_initial_state_and_evaluation_contract(self):
        from harness.story_evidence import matt_pair
        c = control_candidate(enrich_story_fields(matt_redteam_attack('medrec')))
        for changed_contract in (False, True):
            pair = list(copy.deepcopy(matt_pair('matt_medrec')))
            if changed_contract:
                pair[2]['intended_contract']['require_confirmation'] = True
            else:
                pair[0]['initial_records']['med-rec']['warfarin_active'] = 'changed'
            with patch('harness.story_evidence.matt_pair', return_value=pair):
                with self.assertRaisesRegex(ValueError, 'patch changed'):
                    replay_evidence(c)

    def test_rescoring_does_not_claim_repaired_output(self):
        c = control_candidate(enrich_story_fields(agentdojo_tools_attack()))
        r = replay_evidence(c)['replay']
        self.assertEqual(r['originalState'], r['patchedState'])
        self.assertEqual(r['patchedIntent'], 'failed')
        self.assertIn('does not repair', r['limitation'])

    def test_private_oracles_are_not_generator_context(self):
        prompt = json.dumps(attack_search._matt_public_spec('matt_sepsis'))
        for private in ('legitimate_actions', 'control_attack', 'intended_contract', 'corrected', 'E10'):
            self.assertNotIn(private, prompt)

    def test_custom_source_and_outcome_are_unknown(self):
        a = copy.deepcopy(agency_attack()); a['id'] = 'custom'
        s = environment_story(a)
        self.assertFalse(s['canReplay']); self.assertFalse(s['sources'])
        c = control_candidate(a)
        self.assertEqual(c['evidence']['intentStatus'], 'unknown')
        self.assertEqual(c['evidence']['outcomeClass'], 'inconclusive')

    def test_fallback_and_saved_origin_survive_persistence(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(attack_search, 'RUNS_DIR', Path(temp)), \
             patch.object(attack_search, '_openrouter_env', return_value={}), \
             patch.object(attack_search, 'generate_matt_candidates_with_llm', side_effect=RuntimeError('offline')):
            manager = attack_search.JobManager()
            job = manager.start('matt_medrec', None, 1)
            end = time.time() + 10
            while job.status in ('queued', 'running', 'validating') and time.time() < end:
                time.sleep(.02)
            self.assertEqual(job.status, 'done', job.error)
            self.assertEqual(job.generation, 'Programmatic fallback')
            self.assertTrue(job.candidates)
            self.assertEqual(job.candidates[0]['evidence']['provenance']['generation'], 'Programmatic fallback')
            loaded = attack_search.JobManager().get(job.id)
            self.assertTrue(loaded.to_dict()['provenance']['saved'])
            self.assertTrue(loaded.candidates[0]['evidence']['provenance']['saved'])
            self.assertEqual(loaded.candidates[0]['evidence']['candidateDigest'], job.candidates[0]['evidence']['candidateDigest'])
            self.assertIn('candidates', manager.list()[0])

    def test_validation_exception_ends_job_instead_of_sticking(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(attack_search, 'RUNS_DIR', Path(temp)), \
             patch.object(attack_search, '_openrouter_env', return_value={}), \
             patch.object(attack_search, 'generate_matt_candidates_with_llm', side_effect=RuntimeError('offline')), \
             patch.object(attack_search, 'generate_matt_candidates', side_effect=ValueError('bad fixture')):
            manager = attack_search.JobManager()
            job = manager.start('matt_harbor', None, 5)
            end = time.time() + 10
            while job.status in ('queued', 'running', 'validating') and time.time() < end:
                time.sleep(.02)
            self.assertEqual(job.status, 'failed')
            self.assertIn('bad fixture', job.error)


if __name__ == '__main__':
    unittest.main()
