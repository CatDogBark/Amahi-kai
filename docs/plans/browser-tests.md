# Browser tests

A plan, reviewed by Troy (2026-10-09). Built, in two pull requests: the harness, the CI job and
the first four pages (#127), then the rest of the table. The setup wizard's spec waits for the
wizard's redo. The streams needed no new simulated paths: outside production the root helper
records its calls, so a window opens, streams what the page says and finishes.

## Why

Every JavaScript change this week (the `data-call` dispatcher in #121, the scripts moved to files
in #122, the enforced Content-Security-Policy in #123) was checked by Troy clicking through the
NAS. The request specs render every page, but they don't run its JavaScript, so a button that
does nothing, a script the policy refuses, or a page that throws on load gets through CI. The
sign-in page's leftover inline script (#124) is the example: 1511 examples passed with it there.

A browser job closes that gap: a real browser loads the pages as an admin, clicks the things
that matter, and the job fails on any console error or policy violation.

## What it is

- **Capybara system specs** in `spec/system/`, driven by **Cuprite** (Chrome over the DevTools
  protocol; the `cuprite` and `ferrum` gems, pure Ruby, no driver binaries). Chrome is on
  GitHub's runners; on a laptop it's `sudo apt install chromium`, and the specs skip without it.
  Firefox with Selenium was the alternative; Chrome was chosen because its DevTools log reports
  policy violations as security entries, which is the main thing the job is for.
- **Every example fails on noise:** a hook subscribes to the browser's console, JavaScript
  exceptions and log entries, and after each example fails it on any error-level message or
  `securitypolicyviolation`. So a page only passes if it loads clean, before any assertion.
- **The job is small and stays small:** one spec per page area, each a few clicks with one
  assertion that proves the JavaScript ran (text that only a script puts there). No pixel
  checks, no screenshots compared; a screenshot is saved on failure for the CI artifact.
- **Outside production nothing runs:** `Privileged.call` records, installs simulate, so the
  specs exercise the pages against the same stubs the request specs use. Streams without a
  non-production path yet (Greyhole's install, dependency refresh and upgrade, the wizard's
  drive preparation, app installs) get the same short simulated path the others have, so their
  windows can be opened and seen to stream and finish.

## The specs (first batch)

| Page | Clicks | Proves |
| --- | --- | --- |
| Sign in | Open, field focused, sign in as admin | The login page's scripts and the redirect |
| Dashboard | Load; the wrench | Water background initialises; Advanced mode toggles and the page reloads pressed |
| Setup → Shares | Open a card; Get the size; pool copies + and −; Samba settings Save; Create a share | The share page's functions, the dispatcher's args, Saved! |
| Files | The share list; open a share with fixture files; click a file; grid toggle; Download folder notice | The file browser controller, the panel, the zip notice |
| Trash | Keep files select | `data-autosubmit` |
| Settings → System Status | Check now; Update now's confirm (Cancel) | The update check, `data-confirm` |
| Settings → System Dependencies | Check now | The install window opens, streams, finishes, Close & Refresh |
| Apps | Catalog; the Docker switch; an app's install dialog opens and closes | apps.js |
| Users | The lock icon shows the password form; Cancel hides and clears it | `data-reveal` |
| Network → Security | Run audit | security.js, the window, Fix All Issues appears when the simulated audit says so |
| Network → Remote Access | Load; Run security audit | remote_access.js loads clean |
| The setup wizard | With setup incomplete: welcome → admin → network → storage → greyhole → share → complete | `setup.js`, its toasts, the wizard's windows |

Each spec signs in through the real form (the seeded admin, as the request specs do), with no
cookie shortcuts, so the session code is on the path too.

## CI

- A new job, **Browser**, in `.github/workflows/ci.yml`, beside the others: Ubuntu runner, Ruby
  3.2, the test database, `bundle exec rspec spec/system`. Chrome is already on the runner.
- On failure the job uploads `tmp/capybara/` (screenshots and page HTML) as an artifact, so a
  failure can be seen without reproducing it.
- Required for merging, like the others. Expected time: about a minute.
- Flakiness is handled by design, not retries: Capybara waits (up to 5 s) for what it expects,
  no `sleep`, animations reduced (`--force-prefers-reduced-motion`), the water background's
  frame rate doesn't matter to the assertions. A spec that flakes is fixed or deleted.

## Changes to the code

- `Gemfile`: `capybara` and `cuprite` in the test group, locked under Ruby 3.2.3 and Bundler
  2.4.19 as the rules say.
- `spec/system/support/`: the driver setup, the console and policy listeners, `sign_in`.
- Simulated paths for the streams named above (short, like `install_docker_stream`'s).
- `CLAUDE.md` and `CONTRIBUTING.md`: the new job, how to run it locally, that a page must load
  with no console errors.

## In two pull requests

1. **The harness** with the sign-in, dashboard, Shares and Files specs, and the CI job. Proves
   the approach and the job's time.
2. **The rest of the table**, with the simulated stream paths.

Later, when a page changes, its spec changes with it, as the request specs do today. The
phone layout, when it comes, gets a narrow-viewport run of the same specs.

## What it doesn't cover

Anything that only happens on the NAS: real streams, Greyhole, Docker, the root helper. Those
stay with the NAS checklists. And it checks that pages work, not how they look.
