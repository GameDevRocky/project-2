# Commands for Jarman to run: full paths, and say where the `!` goes

When I hand Jarman a command to run himself, write it with ABSOLUTE paths
(`/home/jlion/projects/project-2/...`) and give it without the `!` prefix,
adding "or type it in my prompt box with `!` in front" as the alternative.

Why: on 2026-09-30 I gave `! sudo chown -R jlion:jlion .godot icon.svg.import`.
He ran it in his own WSL terminal, which was sitting in `~`, so the relative
paths did not exist ("No such file or directory"), and in plain bash the `!`
means something else entirely. The `!` prefix only works in Claude Code's
prompt, where it also runs in the project folder.

How to apply: any command meant for his terminal - sudo, apt, chown, git
with credentials - gets full paths and no `!`. Say plainly which window it
goes in.

Related facts from the same fix (Stage 4 prerequisites, both done 2026-09-30):
- `.godot/` and `icon.svg.import` had been owned by root; now `jlion:jlion`,
  so Godot can write imports.
- Blender 5.0.1 (`/usr/bin/blender`, Ubuntu package, Python 3.14) needs the
  apt package `python3-numpy` for its glTF exporter; it is now installed.
