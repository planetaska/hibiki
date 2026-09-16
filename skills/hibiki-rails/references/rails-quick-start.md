# Rails quick start

## Install

```ruby
# Gemfile
gem "hibiki"
gem "hibiki_rails"   # depends on the core gem, turbo-rails >= 2.0, Rails >= 8.0
```

Then `bin/rails g hibiki:rails:install`. Every step checks before it writes, so
re-running is safe.

| File | What the generator does | Skipped when |
| --- | --- | --- |
| `app/javascript/controllers/hibiki_controller.js` | writes the shim `export { default } from "hibiki-rails"`, which registers the packaged controller as `hibiki`; a real controller file, so `stimulus:manifest:update` re-derives it | present |
| `app/javascript/controllers/index.js` | appends `import HibikiController from "./hibiki_controller"` + `application.register("hibiki", HibikiController)` | importmap app (eager-loads the shim), or already registered |
| `app/helpers/application_helper.rb` | injects `include Hibiki::Rails::Helpers` after `module ApplicationHelper` | already included |
| `app/channels/application_cable/channel.rb`, `connection.rb` | stock ActionCable boilerplate (`identified_by :current_user` goes in the connection) | present |

The generator detects an import map by `config/importmap.rb`:

- Importmap app: done. The engine merges `pin "hibiki-rails"` and
  `pin "hibiki-rails/motion"` into the import map from its own
  `config/importmap.rb`, so there is nothing to download.
- Bundler app (esbuild, vite, bun): the generator prints
  `config/importmap.rb not found` and `with a JS bundler, npm/yarn/bun add hibiki-rails instead`.
  Install the npm package at the same version as the gem, because the two ship
  in lockstep and share a private attribute contract.

A missing `index.js` or `application_helper.rb` gets a `skip` notice with the
snippet to add by hand.

## First component

```sh
bin/rails g hibiki:rails:stimulus counter static_pages   # partials under app/views/static_pages
```

```erb
<%= render "static_pages/counter" %>
```

Click `+1` and the count updates live. The other shapes (`island`, `phlex`)
and the CRUD scaffold belong to the `hibiki-rails-scaffold` skill; writing a
channel by hand is `rails-usage.md`.

See also: https://planetaska.github.io/hibiki/the-js-client/
Full docs: https://planetaska.github.io/hibiki/rails-quick-start/
