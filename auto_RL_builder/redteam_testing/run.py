import argparse
import hashlib
import json
from pathlib import Path
from . import proxy
from .evaluate import controls, evaluate

ROOT = Path(__file__).resolve().parent


def run(destination, external_response=None):
    destination.mkdir(parents=True, exist_ok=False)
    files = [ROOT / name for name in ['runtime.py', 'prepare.py', 'evaluate.py', 'proxy.py', 'run.py',
                                      'fixtures/environments.json', 'fixtures/private_oracles.json', 'fixtures/manifest.json']]
    frozen = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    (destination / 'freeze.json').write_text(json.dumps(frozen, indent=2), encoding='utf-8')
    for path in files:
        target = destination / 'frozen_sources' / path.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(path.read_bytes())
    environments = json.loads((ROOT / 'fixtures/environments.json').read_text(encoding='utf-8'))
    oracles = {o['id']: o for o in json.loads((ROOT / 'fixtures/private_oracles.json').read_text(encoding='utf-8'))}
    baseline = controls(environments, oracles)
    (destination / 'control_results.json').write_text(json.dumps(baseline, indent=2), encoding='utf-8')
    if external_response:
        raw = json.loads(external_response.read_text(encoding='utf-8'))
        response = proxy.normalize(raw)
        (destination / 'external_response.raw.json').write_text(json.dumps(raw, indent=2), encoding='utf-8')
    else:
        response = proxy.run(environments, destination / 'proxy')
    assert all(hashlib.sha256(p.read_bytes()).hexdigest() == frozen[str(p.relative_to(ROOT))] for p in files), 'Frozen fixture/scorer changed during call'
    report = evaluate(environments, oracles, response)
    if external_response:
        report['model_role'] = 'Externally supplied response; model identity must be supplied by operator'
    report['frozen_files_verified'] = len(files)
    report['model_calls'] = 0 if external_response else 1
    (destination / 'report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items() if k not in {'cases', 'counterpart_replays', 'limits'}}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--name', default='proxy-01')
    parser.add_argument('--external-response', type=Path)
    args = parser.parse_args()
    if not args.name or Path(args.name).name != args.name or args.name in {'.', '..'}:
        raise ValueError('Run name must be one directory name')
    run(ROOT / 'runs' / args.name, args.external_response)
