# Reactive forms (`Hibiki::Rails::ReactiveForm`)

One declaration replaces the three places a hand-written form object repeats
its attribute list (states, hydrate, commit). Including the module also
includes `Hibiki::Reactive`, so `derived`/`effect` macros and inheritance
work as in the core gem.

## Declaring

```ruby
class TodoForm
  include Hibiki::Rails::ReactiveForm

  reactive_attributes "Todo", :title, :done   # String keeps reloads honest
  reactive_association :tags                  # adds tag_ids; after attributes
  reactive_nested :steps, "StepForm"          # array of child forms

  derived(:title_error) { "can't be blank" if title.strip.empty? }
  derived(:valid?)      { title_error.nil? }
end
```

| Macro | Declares | Notes |
| --- | --- | --- |
| `reactive_attributes model, *names` | one `state` per name, a casting writer | model as Class, String or Symbol; resolved on every use |
| `reactive_association *names` | `<singular>_ids` state, joins `hibiki_attributes` | raises unless `reactive_attributes` came first; cast via target PK type, blanks dropped |
| `reactive_nested name, form_class` | a state holding `[]` of child forms | not in `hibiki_attributes`; serialized as `<name>_attributes` |

## Instance surface

| Method | Behavior |
| --- | --- |
| `.from(record, ...)` | `new(...).hydrate(record)`; the documented constructor (the scaffold does `new` in `build_graph`, then `hydrate` per edit) |
| `#hydrate(record)` | one batch: rebuild children, copy attributes, clear destroy mark, snapshot, clear errors; returns self |
| `#record` | plain ivar reader |
| `#persisted?` | `record&.persisted? \|\| false` |
| `#to_h` | `{ title:, done:, tag_ids:, steps_attributes: [...] }`, reads every signal |
| `#dirty?` | derived: `to_h != snapshot` |
| `#commit` | `record.update(**to_h)`; true and re-hydrate, or false and mirror errors |
| `#commit!` | `commit`, else `record.update!` raising `ActiveRecord::RecordInvalid`; errors already mirrored |
| `#errors` | `record.errors.to_hash` copy from the last failed commit; `{}` after success |
| `#error_for(name)` | `errors[name.to_sym]&.first` |
| `#to_nested_attributes` | `to_h` plus `id:` when persisted and `_destroy:` |
| `#nested_key` | `"c<id>"` or `"n<seq>"`, set by the parent |
| `#mark_for_destruction` / `#marked_for_destruction?` | destroy flag; `hydrate` resets it |

Class readers: `hibiki_attributes` (scalars plus ids, inherited),
`hibiki_model`, `hibiki_nested` (name to form class), `hibiki_nested_form(name)`,
`hibiki_type(name)`, `hibiki_association_type(name)`.

## Casting

Every writer wraps the `state` writer in a prepended module and casts through
`Model.type_for_attribute(name).cast(value)`, so channel payload strings land
as the column type and the write still tracks dependencies:

```ruby
form.done = "0"       # => false
form.priority = "3"   # => 3
```

## Validation, two layers

1. Your deriveds over fields: per keystroke, hand-picked, no queries.
2. The model's `validates` at `commit`: authoritative, mirrored into `#errors`
   as a fresh hash (a live `ActiveModel::Errors` object would defeat the
   equality gate).

Stream one field's message as a reactive value:

```ruby
transmit_value(:title_error) { @form.error_for(:title) }
```

Generated forms (scaffold and `hibiki:rails:form`) add:

```ruby
derived(:live_errors) { { title: ("can't be blank" if title.to_s.strip.empty?) }.compact }
derived(:valid?) { live_errors.empty? }
def error_for(name) = super || (live_errors[name.to_sym] if dirty?)
```

Live clauses come only from validators a form can check from the typed value
(presence, length, numericality bounds without `allow_nil`/`allow_blank`);
anything gated on `if:`/`unless:`/`on:` waits for commit.

## In a channel

Build `@form = TodoForm.new` in `build_graph`, `hydrate` per edit, guard
each write with `hibiki_attributes.include?`, and `return unless
@form.commit` in `save` (the SKILL.md "Using it in a channel" section has
the code). Submit with `on(:save, event: :submit, reset: false)`. Use
`from(Todo.new)` for create; `commit` INSERTs and `persisted?` flips after
the re-hydrate.

## Regenerating

`bin/rails g hibiki:rails:form Book [field:type ...]` rewrites
`app/forms/book_form.rb`, `_form.html.erb`, `_book_form.html.erb` (Phlex:
`form.rb`, `row_form.rb`). Options: `--skip-views`, `--css=NAME`, `--phlex`.
Refuses without a model ("No model Book") or table ("has no table yet").

See also: https://planetaska.github.io/hibiki/crud-notes/
Full docs: https://planetaska.github.io/hibiki/reactive-forms/
