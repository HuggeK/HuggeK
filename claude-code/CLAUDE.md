# Global instructions (apply to every project)

## Language conventions

- Write **all code identifiers in English** — variable, function, class,
  type, parameter, and file names — regardless of the language used in the
  prompt, chat, or comments.
- Write **all invented / placeholder data in English** as well: JSON keys
  and made-up string values, enum members, config keys, environment
  variable names, database/column field names, and sample/fixture/mock
  data.
- **Exception:** genuine human-facing content that is meant to be in another
  language stays in that language — UI copy, user-visible strings,
  translation files, and localized test fixtures whose value is the point.

## Host machine safety

- **Never install software on the host machine without asking me first.**
  Always state what you want to install and why, then wait for my explicit
  approval before running anything that installs. This includes:
  - System / package managers: `winget`, `choco`, `scoop`, `npm i -g`,
    `pip install`, `go install`, `cargo install`, `apt`, `brew`, etc.
  - Downloading and executing any binary, installer, or script
    (`curl … | sh`, `iwr … | iex`, running a downloaded `.exe`/`.msi`).
  - Anything that places a new tool/binary on the machine or modifies
    globally-installed tooling.
- Reading, searching, building, and running existing project tooling is
  fine without asking. The gate is specifically about **adding new software
  to the host.**
- **Cite any software before proposing I install it.** When you ask for
  approval to install a program/package/binary, first present it with
  reference links so I can judge it before saying yes:
  - A **Wikipedia** link, *if a relevant article exists* (say so if none does).
  - The **official project / home page** and the **source repository**.
  - For an open-source library, its **star count** (e.g. GitHub stars). If the
    project isn't hosted somewhere with stars (e.g. self-hosted Heptapod/GitLab),
    say that explicitly instead of guessing a number.
  - Render every reference as a clickable markdown link, and keep it brief —
    a short line or two per candidate, then wait for my go-ahead.

## Output formatting

- **Make file links clickable.** Whenever you give me a path to a file I
  might want to open, render it as a markdown link to a `file://` URI —
  e.g. `[name.txt](file:///C:/Users/hugok/name.txt)` — using an absolute
  path with forward slashes. A bare path in backticks is not clickable in
  the terminal, so always use the linked form when the intent is for me to
  open the file.
- **Always give me a clickable link to anything you publish on GitHub.**
  Whenever you create or update something on GitHub — a commit, a PR, an
  issue, a comment, a review, a release, a tag — finish by giving me the
  direct `https://github.com/…` URL to that exact thing as a clickable
  markdown link I can tap to open it. Not just the number or SHA; the full
  permalink.
  - **Commit** → `https://github.com/<owner>/<repo>/commit/<sha>`
  - **PR** → `https://github.com/<owner>/<repo>/pull/<number>`
  - **Issue** → `https://github.com/<owner>/<repo>/issues/<number>`
  - **A specific comment / review** → use the anchored permalink (e.g.
    `…/pull/<number>#issuecomment-<id>` or `#discussion_r<id>`); `gh` prints
    this URL in its output, so use that rather than just linking the PR.
  - **Release / tag** → `https://github.com/<owner>/<repo>/releases/tag/<tag>`
  - Render every one as `[label](url)`, never a bare SHA/number in backticks.
- **Use collapsible dropdowns for clarifications in GitHub PR/issue text.**
  When a PR or issue description (or comment) needs extra clarification,
  background, or detail that would clutter the main read, hide it in a
  markdown expandable dropdown so the body stays skimmable:

  ```markdown
  <details>
  <summary>Short label of what's inside</summary>

  The clarification / detail / rationale goes here.

  </details>
  ```

  Keep the headline narrative readable on its own; tuck the deeper
  clarifications into `<details>` blocks the reader can expand on demand.
  (Keep the blank lines inside the block so the markdown renders.)

## Git commit authorship

- **The AI model that wrote the code is the commit _author_; I am the
  _co-author_.** This is the reverse of the usual default — apply it to
  every commit you create.
  - **Author** = your own current model identity, with Anthropic's noreply
    address, e.g. `Claude Opus 4.8 <noreply@anthropic.com>` (substitute
    whatever model you actually are).
  - **Co-author** = me, as a trailer on the last line of the commit message:
    `Co-authored-by: HuggeK <48095810+HuggeK@users.noreply.github.com>`.
  - The **committer** stays my git identity (do not change it) — only the
    author and the co-author trailer differ from the default.
- Concretely, commit like:
  `git commit --author="Claude Opus 4.8 <noreply@anthropic.com>" -m "<subject>" -m "Co-authored-by: HuggeK <48095810+HuggeK@users.noreply.github.com>"`
- Do **not** add yourself (the model) as a `Co-authored-by` trailer — you are
  the author, so a co-author trailer for yourself would be redundant.
