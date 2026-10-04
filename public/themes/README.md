# Themes

Each theme serves plain CSS from `<theme>/stylesheets/style.css`; the app links it directly. `<theme>/src/` holds the Sass
they were built from. Nothing compiles Sass on a NAS: after editing a theme's source, rebuild
its CSS with [Dart Sass](https://sass-lang.com/dart-sass/) and commit both, for example:

```
sass --no-source-map public/themes/amahi-kai/src/style.scss public/themes/amahi-kai/stylesheets/style.css
```
