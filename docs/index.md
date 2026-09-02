---
layout: home
hero:
  name: Hibiki (響き)
  text: Svelte-style signals for Ruby
  tagline: Hibiki is a fine-grained reactivity library modeled on the signal system in Svelte 5.
  image:
    src: /assets/img/logo.svg
    alt: Logo
    width: 320
    height: 320
  actions:
    - theme: alt
      text: Introduction
      link: /introduction/
    - theme: brand
      text: Get Started
      link: /getting-started/
    - theme: alt
      text: GitHub
      link: https://github.com/planetaska/hibiki
features:
  - icon: ᛟ
    title: Rune style syntax
    details: The three primitives from Svelte 5's runes. Writable state, lazy derived values, and eager effects.
    link_text: Learn more
    link: /getting-started/#the-three-primitives
  - icon: 𖣂
    title: Opt-in DSL
    details: Bare state / derived / effect helpers when you include Hibiki::DSL — or skip it and use the plain classes.
    link_text: Learn more
    link: /getting-started/#two-flavors
  - icon: ᚨ
    title: Class-based reactivity
    details: Declare signals with class-level macros and use them as plain attributes. Svelte 5 rune fields, in Ruby.
    link_text: Learn more
    link: /class-based-reactivity/
---
