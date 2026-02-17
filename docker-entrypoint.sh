#!/bin/bash
set -e

echo "==> Waiting for database..."
until mysqladmin ping -h "$DATABASE_HOST" --silent 2>/dev/null; do
  sleep 1
done
echo "==> Database is ready!"

# Create database if it doesn't exist
echo "==> Setting up database..."
bundle exec rails db:create 2>/dev/null || true
bundle exec rails db:migrate

# Seed if the users table is empty (first run)
USER_COUNT=$(bundle exec rails runner "puts User.count" 2>/dev/null || echo "0")
if [ "$USER_COUNT" = "0" ]; then
  echo "==> First run detected — seeding database..."
  bundle exec rails db:seed
fi

# Precompile assets if not already done
if [ ! -d "public/assets" ] || [ -z "$(ls -A public/assets 2>/dev/null)" ]; then
  echo "==> Precompiling assets..."
  bundle exec rails assets:precompile
fi

echo "==> Starting Amahi-kai..."
exec "$@"
