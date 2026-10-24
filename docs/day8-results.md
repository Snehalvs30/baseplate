
## A code fix released through GitOps (Footnote)

Bug: the source panel highlighted loosely related sentences in sources the answer
never cited (it matched keywords against the whole answer as a fallback).

1. Fixed in the Footnote repo; CI linted, tested, built for amd64 and arm64, and
   published `ghcr.io/snehalvs30/footnote:sha-97b7e32`.
2. The release was one line in this repo: Footnote's image tag, from `latest` to
   `sha-97b7e32` (pull policy IfNotPresent, since pinned tags never change).
3. ArgoCD rolled it out; the new pod became ready before the old one stopped, and
   the database was untouched.

Uncited sources now show no highlight and a note saying they weren't cited. Rolling
back would be the same one-line change, back to the previous tag.

Also found: Footnote doesn't detect duplicate uploads (the handbook added twice gave
six sources from the same file). Future improvement: hash each file's content and
reuse an existing document.
