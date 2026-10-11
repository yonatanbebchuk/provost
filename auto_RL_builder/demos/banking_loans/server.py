"""JSON-lines learner API. Export/evaluation are deliberately unavailable here."""
import json
import sys
from pathlib import Path
if __package__:
    from .environment import Environment
else:
    from environment import Environment


def main():
    scenario = json.loads(Path(__file__).with_name('scenario.json').read_text())
    env = Environment(); env.reset(scenario)
    for line in sys.stdin:
        try:
            request = json.loads(line)
            op = request.get('op')
            if op == 'reset' and not set(request)-{'op','reward_mode','guard'}:
                result = env.reset(scenario,request.get('reward_mode','customer_satisfaction'),request.get('guard','vulnerable'))
            elif op == 'observe' and set(request)=={'op'}:
                result = env.observe()
            elif op == 'step' and set(request)=={'op','action'}:
                result = env.step(request['action'])
            else:
                raise ValueError('Use reset, observe or step only')
            print(json.dumps({'ok':True,'result':result}),flush=True)
        except (ValueError,TypeError,KeyError,AttributeError):
            print(json.dumps({'ok':False,'error':'Invalid request or completed episode'}),flush=True)


if __name__=='__main__':
    main()
