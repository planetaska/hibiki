# Nested forms (`reactive_nested` + `Hibiki::Rails::NestedActions`)

A parent form holds an array of child forms in one signal; rows are added,
edited, reordered and removed while the form stays open, and one `commit`
persists the tree through `accepts_nested_attributes_for`.

## Form side

```ruby
class SongForm
  include Hibiki::Rails::ReactiveForm
  reactive_attributes Song, :title
  reactive_nested :credits, "CreditForm"   # CreditForm may nest again
end
```

| Call on the parent form | Effect |
| --- | --- |
| `nested_add(:credits)` | appends a child hydrated from `Credit.new`, key `n<seq>`; returns it |
| `nested_remove(:credits, child)` | persisted: `mark_for_destruction`; new: dropped from the array |
| `nested_move(:credits, child, to:)` | index among visible (unmarked) siblings, clamped; marked rows never move |
| `to_h` | adds `credits_attributes: [child.to_nested_attributes, ...]` |
| `commit` | one save; child errors distributed onto the matching child forms; association reset after either outcome |

Cancel is the undo: closing without saving discards the form's copy of the
tree, destroy marks included.

## Channel side

Include `Hibiki::Rails::NestedActions` next to `Hibiki::Rails::Channel`.
Every public method becomes an action on purpose:

| Action | Payload keys | Does |
| --- | --- | --- |
| `nested_add` | `dom`, `path` (a collection) | `owner.nested_add(name)` |
| `nested_remove` | `dom`, `path` (a child) | `owner.nested_remove(name, child)` |
| `nested_move` | `dom`, `path`, `to` | `owner.nested_move(name, child, to: to.to_i)` |
| `nested_set_field` | `dom`, `path`, `field`, and the value under `"#{path}/#{field}"` | writes the child's field if declared |

Path grammar: association names alternating with child keys, any depth.

```
"credits"                        # collection
"credits/c3"                     # persisted child id 3
"credits/c3/contributions/n1"    # new grandchild
```

Every hop is gated (`hibiki_nested` key, live child key, child
`hibiki_attributes`), so a stale or forged path drops the action. The private
`nested_form_for(dom)` resolves `dom` ending in `_new` to `@new_form` when
`@creating`, otherwise `@form` when `@editing_id`; override it on a channel
with different ivars.

Generated inputs (ERB shown):

```erb
<%= text_field_tag "#{path}/role", credit.role, id: "#{dom_path}_role",
      **on(:nested_set_field, event: :input, with: { dom: dom, path: path, field: "role" }) %>
<%= tag.button("Remove", type: "button", **on(:nested_remove, with: { dom: dom, path: path })) %>
<%= tag.button("↑", type: "button", **on(:nested_move, with: { dom: dom, path: path, to: index - 1 })) %>
```

Input names `"#{path}/#{field}"` stay unique per child and inert in a full
page submit, where only declared scalars are assigned.

## Generator

```sh
bin/rails g hibiki:rails:nested Song Credit role:string position:integer
bin/rails g hibiki:rails:nested Credit Contribution part:string   # one level deeper
bin/rails db:migrate
```

One parent to child edge per run; depth is composition. An existing child
(migrated, `belongs_to :song`) takes the field list as order and subset only.
A missing child is created via `active_record:model` with `song:references`
prepended. A run whose parent is itself a nested child (its `_credit_fields`
partial exists) nests into that partial.

| Written or modified | Content |
| --- | --- |
| `app/forms/credit_form.rb` | ReactiveForm over the child's columns, minus the foreign key and position |
| `app/views/songs/_credit_fields.html.erb` | one row: inputs, remove, up/down when ordered (Phlex component under `--phlex`) |
| `app/models/song.rb` | `has_many :credits` (ordered scope when ordered), `accepts_nested_attributes_for ... allow_destroy: true` |
| `app/forms/song_form.rb` | `reactive_nested :credits, "CreditForm"`; a `to_h` override stamping positions when ordered |
| `app/channels/songs_channel.rb` | `include Hibiki::Rails::NestedActions` once; `includes(...)` preloads on form-opening actions |
| `_form.html.erb`, controller | classic `fields_for` fieldset and the `credits_attributes` group in `params.expect` |

| Option | Effect |
| --- | --- |
| `--position=COLUMN` | order by COLUMN; migration added when the column is missing |
| `--skip-position` | unordered even with a `position` column |
| `--phlex` / `--css=NAME` | detected from the scaffold when absent |

Notices: `migrate` (child or position column generated), `assoc` (a
`belongs_to` option label guess). A created child is never ordered silently;
put `position` in its field list or pass `--position`.

Full docs: https://planetaska.github.io/hibiki/nested-forms/
