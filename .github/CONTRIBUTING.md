# Contributing to Amahi-kai

## Setting up

For a real install (recommended for anything that touches the system), use a dedicated Ubuntu
24.04 machine or VM:

```bash
git clone https://github.com/CatDogBark/Amahi-kai.git
cd Amahi-kai
sudo bin/amahi-install
```

For working on the code and running tests, you need Ruby 3.2 and SQLite:

```bash
bundle install
RAILS_ENV=test bundle exec rails db:schema:load
```

## Tests

Tests use SQLite and never change the system: outside production `Privileged.call` records
calls instead of running the root helper. Commands that only read the system (`Shell.output`,
`Shell.success?`) do run, so specs stub them. CI runs these groups (and the first and third again
on MariaDB):

```bash
bundle exec rspec spec/models/ spec/services/ spec/helpers/
bundle exec rspec spec/lib/
bundle exec rspec spec/requests/
```

Lint and security checks (installed as gems, not in the bundle): RuboCop 1.91.0 with
rubocop-rails 2.38.0 and rubocop-rspec 3.10.2, Brakeman 8.1.0, bundle-audit 0.9.3. RuboCop fails
on any offense; Brakeman fails on anything not in
`config/brakeman.ignore`, and every entry there needs a note.

## Making a change

- One change per pull request, with specs; CI must pass.
- Add a line to `CHANGELOG.md` (Unreleased), written for the people who use Amahi-kai.
- Anything that needs root is an operation in `libexec/amahi-helper` (arguments, validation and
  logging), called with `Privileged.call`. Don't add sudoers rules.
- Run commands as argument lists (`Open3.capture3('systemctl', 'show', unit)`), not strings through
  a shell.
- Migrations must be safe to run twice and must work with the previous version's code: an update
  that fails rolls the code back, not the database.
- Change `Gemfile.lock` only under Ruby 3.2 with Bundler 2.4.19, so it resolves gems the servers'
  Ruby can run.
- Views are Slim or ERB; JavaScript is plain JavaScript and Stimulus (`app/assets/javascripts`);
  every fetch sends the CSRF token (`csrfHeaders()`).

## License

GNU AGPL v3. Contributions must be compatible with it.
