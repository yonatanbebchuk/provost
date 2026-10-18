# Provost

An alignment management system for RL training environments, built in 48 hours with Josh, Hai, Matt & Alvaro.

Before an enterprise trains a model in an environment, Provost trains a policy against it on purpose,
flags the rollouts that earned reward by breaking the human intent, proposes the changes to the reward
and objective that close those hacks, rechecks them on the hardened environment, and certifies the result.

![Provost](docs/slides/01-provost.png)

## Why

Reward hacking has moved from a research curiosity to a production incident.

![Background](docs/slides/02-background.png)

Every company will train its own models, and every one of those training runs needs an
environment the model cannot cheat.

![The RL Renaissance](docs/slides/03-rl-renaissance.png)

![A window into the future](docs/slides/04-window-into-the-future.png)

## What it does

The product is a native macOS app. Environments are the objects. Each environment page reads like
a README: the objective and its constraints, the training data, the reward, the action space, the
observation space, and the certificate.

![The environment](docs/slides/demo-1-environment.png)

**Compile** trains a policy against the environment and streams the rollouts back. Rollouts that
earned reward by breaking the human intent are flagged as hacks, with the step that caused them,
the reward they earned, and whether the objective was actually met. The result is **Stable** or
**Unstable**.

![Unstable: two hacks found](docs/slides/demo-2-unstable.png)

**Harden** takes the hacks and proposes the differences that close them, grouped by the part of the
environment they change: a new reward gate, a rewritten reward function, a tighter objective. Each
difference can be accepted or rejected; accepted ones edit the environment and go into its change
record. **Recheck** replays a hack against the hardened environment to confirm it no longer pays.
A compile that comes back Stable can issue a signed certificate.

![Harden: the differences that close the hacks](docs/slides/demo-3-harden.png)

## Business

![A creative monopoly](docs/slides/05-business.png)

![Unfair advantage](docs/slides/06-unfair-advantage.png)

![Close](docs/slides/07-close.png)

## Repository layout

| Path | What it is |
|------|------------|
| `interface/` | The Provost macOS app (SwiftUI, Xcode 27). The pitch deck lives inside it; see [`interface/README.md`](interface/README.md) for build, run and pitch mode. |
| `interface/Resources/fixtures/` | Bundled demo environments, including the bank-loan environment shown above. |
| `auto_RL_builder/` | Demo environments used to generate fixtures (for example the banking-loans reward function). |
| `environements/` | Downloaded RL environments (Hugging Face, Prime Intellect, Karotte) that were red-teamed. |
| `scripts/`, `exploits/`, `ui/` | The reward-hack red-team pipeline: attack generators, saved exploit evidence, and a static diff-studio UI. See [`docs/REWARD_HACK_REDTEAM.md`](docs/REWARD_HACK_REDTEAM.md). |
| `docs/` | Attack write-ups, root-cause and remediation notes, and the slides in this README. |

## Running the app

Requires macOS 26, Xcode 27 and `xcodegen` (`brew install xcodegen`).

```bash
cd interface
make run     # build and open the app
make pitch   # build and open straight into the pitch deck
```

The app runs the whole demo on bundled fixture data; no backend or API key is needed. In the app,
click the Provost logo or press Present to start the pitch from slide 1. The demo slide hands over
to the live app and **Continue pitch** returns to the deck.
