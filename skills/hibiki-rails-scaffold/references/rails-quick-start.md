# Rails quick start, scaffold-angled (digest)

```ruby
# Gemfile
gem "hibiki"
gem "hibiki_rails"
```

```sh
bin/rails g hibiki:rails:install
```

The install writes the `hibiki_controller.js` shim, registers it in
`controllers/index.js` on jsbundling apps, includes `Hibiki::Rails::Helpers`
in `ApplicationHelper`, and creates the `ApplicationCable` files. Importmap
apps are done. Bundler apps (esbuild, vite, bun) also run `npm install
hibiki-rails` (or yarn/bun), pinned to the gem's version, since the two
release in lockstep.

Then either a whole resource or one component:

```sh
bin/rails g hibiki:rails:scaffold Book title:string author:references   # then db:migrate, restart
bin/rails g hibiki:rails:stimulus counter static_pages                  # renders as "static_pages/counter"
```

Render a component with `<%= render "static_pages/counter" %>`; visit
`/books` for the scaffold. Only `stimulus` works before the install; the
scaffold, `island` and `phlex` print a `hint` until it has run.

Full docs: https://planetaska.github.io/hibiki/rails-quick-start/
