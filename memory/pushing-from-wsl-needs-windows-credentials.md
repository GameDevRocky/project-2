# Pushing from the WSL checkout needs a one-off identity and Windows' login

The WSL checkout at `/home/jlion/projects/project-2` has no git identity and no
GitHub credentials of its own. A plain `git commit` fails with "Author identity
unknown", and a plain `git push` fails with "could not read Username".

What worked on 2026-09-28, without changing any git config:

    git -c user.name="jarmanper" -c user.email="jarmanperry7@gmail.com" commit ...
    git -c credential.helper= \
        -c credential.helper="/mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager.exe" \
        push -u origin <branch>

`jarmanper <jarmanperry7@gmail.com>` is the identity on all of Jarman's earlier
commits in this repo. The credential helper is Git for Windows' Credential
Manager, which already holds his GitHub login.

Why: the first push of the `visual-overhaul` branch failed twice on these two
missing pieces before going through.

How to apply: only commit or push when Jarman asks (CLAUDE.md). When he does,
use the two commands above rather than editing `~/.gitconfig`. If he ever wants
it permanent, `git config --global` with the same values is a one-time fix, but
ask first.
