---
title: Lifecycle in detail
nav_order: 2
---

# Lifecycle in detail

Expand on the following:

A root's block runs untracked, and a root created inside an effect is *not* adopted by it — it deliberately escapes the automatic owner tree, so its lifetime is exactly `Hibiki.root` … `root.dispose`. Individual effects can still be disposed directly with `Effect#dispose`.
