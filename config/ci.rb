# Run using bin/ci — every check of the CRM in one command with a short pass/fail summary.
# Agents run this instead of the individual commands (less output, fewer tokens).

CI.run do
  # Brakeman and RuboCop scan through a brace-free path: Ruby globs break on the {vpc} folder name.
  step "Style: Ruby", "ln -sfn \"$PWD\" /tmp/vpc-crm-ci && bin/rubocop /tmp/vpc-crm-ci"
  step "Code loading: Zeitwerk", "bin/rails zeitwerk:check"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Importmap audit", "bin/importmap audit"
  # Brakeman finds nothing under a path with glob characters (the local {vpc} folder),
  # so it scans through a brace-free symlink.
  step "Security: Brakeman", "ln -sfn \"$PWD\" /tmp/vpc-crm-ci && bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error -p /tmp/vpc-crm-ci"

  step "Tests: Rails on PostgreSQL", "bin/rails db:test:prepare test"
  step "Data safety: Git index", "python3 scripts/check-repository-data.py"
  step "Data safety: ignore rules", "python3 -m unittest discover -s tests -p 'test_*.py'"
  step "Deploy: Kamal config", "env KAMAL_HOST=203.0.113.10 CRM_HOST=crm.example.test bin/kamal config > /dev/null"

  # A green commit status on GitHub without paid CI minutes (agreed per repository):
  #   gh extension install basecamp/gh-signoff && gh signoff install
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
