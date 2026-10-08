# Themes

Each theme serves plain CSS from `<theme>/stylesheets/style.css`; the app links it directly. `<theme>/src/` holds the Sass
they were built from. **amahi-kai's `style.css` is now edited directly**: its `src/` predates the
ocean theme and the October 2026 refresh (the block at the end of `style.css`), so rebuilding it
would lose them. Nothing compiles Sass on a NAS: after editing a theme's source, rebuild
its CSS with [Dart Sass](https://sass-lang.com/dart-sass/) and commit both, for example:

```
sass --no-source-map public/themes/amahi-kai/src/style.scss public/themes/amahi-kai/stylesheets/style.css
```
