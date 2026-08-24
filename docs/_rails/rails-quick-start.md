---
title: Quick start
nav_order: 2
---

# Rails quick start

## Installation

**Step 1** — Add the gems (`hibiki_rails` depends on the core `hibiki` gem):

```ruby
# Gemfile
gem "hibiki"
gem "hibiki_rails"
```

Or `gem install hibiki hibiki_rails`.

**Step 2** — Run the install generator:

```sh
bin/rails g hibiki:rails:install
```

The generator detects whether your app uses an import map:

- For importmap apps, installation is fully automatic — you are done.
- Bundler apps (esbuild, vite, bun, ...) need to install the companion JS client, published as the npm package `hibiki-rails`. Install it with your package manager:
  - `npm install hibiki-rails`
  - `yarn add hibiki-rails`
  - `bun add hibiki-rails`
  - or the equivalent for your setup

## Generate your first reactive component

The generators scaffold a working reactive component:

```sh
# Replace [your_view_path] with your desired view path,
# e.g. counters, posts, users/profile...
bin/rails g hibiki:rails:stimulus counter [your_view_path]

# For example, this creates "counter" component partials
# inside app/views/static_pages
bin/rails g hibiki:rails:stimulus counter static_pages
```

This creates a minimal working reactive component in the given view path.

## Render the reactive component

The generated components are ordinary Rails partials (or Phlex components, if you used the Phlex generator), so render one like any other partial:

```erb
<%= render "static_pages/counter" %>
```

Congratulations! You now have your first reactive component — click `+1` and watch it live-update.

From here: [Generators]({{ "/generators/" | relative_url }}) covers the other component shapes, and [Rails usage]({{ "/rails-usage/" | relative_url }}) shows how to write a channel by hand.
