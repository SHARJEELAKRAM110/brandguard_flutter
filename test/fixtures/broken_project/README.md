# INTENTIONALLY BROKEN FIXTURE

Used by BrandGuard integration tests. Brand `beta` contains:

1. A missing logo (assets/brands/beta/logo.png).
2. A launcher icon that is a byte copy of alpha's icon.
3. A staging URL in config/beta/production.json.
4. A German translation missing the `logout` key.
5. An iOS bundle ID copied from alpha (beta.xcconfig).
6. A wrong Android app name (manifestPlaceholders).
