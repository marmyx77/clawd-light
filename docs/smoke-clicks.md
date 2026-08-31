# Live clicks, last checked

Written by `Scripts/smoke-clicks.sh`. Not a gate: it needs a screen, an
unlocked session and other people's applications running, so it cannot be a
condition for merging. It is the record that the README's `live` column
rests on.

- **When:** 2026-08-31 08:23
- **Build:** 0.1.0, signed by Developer ID Application: Marco Armellino (33Z4MPR4FF)
- **Mode:** recognition only, nothing moved

| Slot | Row | Should lead to | Result | Window |
|---|---|---|---|---|
| 2 | AW events | an editor window | recognised | — |
| 4 | sito-aworld | an editor window | recognised | — |
| 5 | Virgilio | an editor window | recognised | — |
| 6 | Clawd Light <logo | an editor window | recognised | — |
| 7 | AI literacy | an editor window | recognised | — |

**Not exercised**, because no session of that kind was running:

- a Remote-SSH window
- the ChatGPT app
- the Claude desktop app

**Out of reach of this script**, because they sit past the ninth row and
`open` addresses slots. The panel's own click reaches them; nothing on the
command line does:

- marcoarmellino — the terminal holding its tab
- Exit — an editor window
- aworld-os-platform — an editor window
- writer — the terminal holding its tab
- yt — the terminal holding its tab
- voci-digest — the terminal holding its tab

Anything named above is something this run says nothing about.
