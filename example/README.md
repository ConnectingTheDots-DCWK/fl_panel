# fl_panel example

An IDE-shaped demo of the docking layout: files at a fixed width, editors in
the middle, tools on the right that only group with other tools, a console
along the bottom; a style switcher, a button that opens twelve editors to watch
the strip scroll, a focus menu, a context menu, an unsaved dot that makes the
close guard ask, and save/restore of the layout. It is not a sample: the
pre-commit hooks run its suite on any change to `lib/`, because it is the only
thing that exercises the docking end to end.

```sh
fvm flutter run -d linux
```

It is also [live on GitHub Pages](https://connectingthedots-dcwk.github.io/fl_panel/),
built for the web from `main` by `../.github/workflows/demo.yml`.
