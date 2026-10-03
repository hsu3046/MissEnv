#!/usr/bin/env python3
"""Create disposable fixtures with invented values, never inspect the user's projects."""
from pathlib import Path

root = Path(__file__).resolve().parent.parent / "work" / "demo"
fixtures = {
    "atlas-web/.env.local": '''# Atlas · local development
# Example values only. No real credentials.
NODE_ENV=development
NEXT_PUBLIC_APP_NAME="Atlas"
NEXT_PUBLIC_APP_URL=http://localhost:3000

# Data & services
DATABASE_URL="postgresql://demo:example@localhost:5432/atlas"
REDIS_URL=redis://localhost:6379
SUPABASE_URL=https://demo-project.supabase.co
SUPABASE_ANON_KEY="example-placeholder"

# Feature flags
ENABLE_ANALYTICS=false
ENABLE_PREVIEW=true
LOG_LEVEL=debug
PORT=3000
''',
    "atlas-web/.env.example": '''# Shared template
NODE_ENV=development
NEXT_PUBLIC_APP_NAME="Atlas"
NEXT_PUBLIC_APP_URL=
DATABASE_URL=
REDIS_URL=
SUPABASE_URL=
SUPABASE_ANON_KEY=
ENABLE_ANALYTICS=false
ENABLE_PREVIEW=false
LOG_LEVEL=info
PORT=3000
SENTRY_DSN=
''',
    "atlas-web/.env.production": '''# Production example · invented values
NODE_ENV=production
NEXT_PUBLIC_APP_NAME="Atlas"
NEXT_PUBLIC_APP_URL=https://atlas.example.com
DATABASE_URL="example-placeholder"
REDIS_URL="example-placeholder"
ENABLE_ANALYTICS=true
ENABLE_PREVIEW=false
LOG_LEVEL=warn
PORT=3000
''',
    "orbit-api/.env": '''# Orbit API · development
APP_NAME=orbit-api
PORT=4000
DATABASE_URL="postgresql://demo:example@localhost:5432/orbit"
REDIS_URL=redis://localhost:6379/1
LOG_LEVEL=debug
RATE_LIMIT=100
ALLOWED_ORIGINS="http://localhost:3000"
''',
    "orbit-api/.env.example": '''APP_NAME=orbit-api
PORT=4000
DATABASE_URL=
REDIS_URL=
LOG_LEVEL=info
RATE_LIMIT=100
ALLOWED_ORIGINS=
''',
    "studio-site/.env.local": '''# Studio · local
SITE_TITLE="Studio"
SITE_URL=http://localhost:4321
PUBLIC_ANALYTICS_ID="example-placeholder"
PREVIEW_MODE=true
''',
    "studio-site/.env.example": '''SITE_TITLE="Studio"
SITE_URL=
PUBLIC_ANALYTICS_ID=
PREVIEW_MODE=false
''',
}
for relative, content in fixtures.items():
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    # Avoid accidentally resetting edits when the demo is launched again.
    if not path.exists():
        path.write_text(content, encoding="utf-8")
print(root)
