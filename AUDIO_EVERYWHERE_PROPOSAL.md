# Audio-Everywhere Proposal — Speech-to-Text for Social-Media Recipe Imports

> Status: **PROPOSAL / DEFERRED** — research complete, no code started.
> Authored 2026-05-30. Reconstructed from the recipe-import session transcript
> (session `5bf27cb9`) + handoff `/tmp/food-app-handoff.md §5`. The original
> research lived only in the transcript and was never written to a durable file;
> this doc is that durable record.
> Sequencing: the user wants this tackled **after** the recipe UI work (Phase 2,
> build 44), as a **separate phase** and likely with a **different agent**.
> Gate: **cost + ToS discussion required before any code.**

---

## 1. The core question

> "I share an Instagram / TikTok / Facebook video → the app should get the
> **audio**, run **speech-to-text**, then have Gemini structure it. Because not
> everyone writes a caption."

That instinct is **correct** and is a **real product gap today** — not a
misunderstanding. This proposal is about closing it.

---

## 2. How it works today (the two services — do not conflate them)

There are **two separate AI services** in the recipe pipeline:

| Service | Model | Key | Job |
|---|---|---|---|
| **Speech-to-text** | **Groq Whisper** `whisper-large-v3-turbo` | `GROQ_API_KEY` | Audio → transcript |
| **Structuring / cleanup / image vision** | **Gemini** `gemini-3.1-flash-lite` | `GEMINI_API_KEY` | Transcript/caption/image → structured recipe |

Gemini does **not** do speech-to-text. Whisper does **not** structure. They run
in sequence: **audio → Whisper STT → Gemini cleanup.**

### The three import lanes

| How the user imports | Lane / endpoint | Uses audio + STT? | Uses caption? |
|---|---|---|---|
| **Pastes a link** (in-app browser) | `structure-text` | ❌ no | ✅ caption only |
| **Shares a video file** (share extension) | `import-from-audio` | ✅ Whisper STT | ❌ no |
| **Pastes a website/blog URL** | `import-from-url` | ❌ no | ✅ page text |

All three now run Gemini structuring (shipped 2026-05-30). But note the asymmetry
in the first two rows — that is the gap.

---

## 3. The gap (root cause)

**Pasting a social link never touches speech-to-text.** It opens an in-app
`WKWebView`, scrapes the **caption text only**, and structures that. The audio /
Whisper lane *only* fires when a **video file** is shared through the iOS share
extension.

Why the link path can't just "also grab the audio":

- **Instagram/TikTok pages do not expose the underlying video file to a
  webview.** There is no DOM/API surface a client-side browser can pull the media
  from. So the link lane is structurally limited to whatever the caption contains.
- Captions are unreliable: many reels have a partial caption, a section header
  in place of a title, macros mixed into ingredients, or no recipe text at all.
  (Observed live: a "Mediterranean Bowl" reel imported caption-shaped and partial.)

**Getting audio from a pasted link therefore requires server-side video
download** (yt-dlp / cobalt-style fetch of the public URL) — a genuinely new
backend capability with real cost and ToS implications. That is the heart of this
proposal.

> Note: the caption lane itself was *also* improved this session (made
> extraction-first so Gemini reads the whole caption instead of a lossy
> heuristic pre-pass). That fix is independent and already shipped — it makes the
> caption path as good as it can be, but it cannot invent audio the caption never
> contained.

---

## 4. Competitor research — Recime

Recime (a leading recipe-import app) was studied as the reference implementation.

**What Recime does:** caption → **audio-transcription** → website, via a
**server-side pipeline triggered by the iOS share sheet**, operating on a
**single public URL** at a time.

Key takeaways:
- Serious recipe apps **do** transcribe audio for no-caption videos — confirming
  the user's instinct.
- It is their **most expensive operation** — which is why Recime caps free users
  at **~5 imports/week**. Transcription cost is the constraint that shapes the
  whole product/pricing model.
- The pattern they use (share-extension-triggered, server-side, single-URL) is
  also the **legally defensible** one (see §5).

---

## 5. ToS / legal posture

- Server-side video download technically **violates Instagram/TikTok Terms of
  Service** (no automated downloading).
- **However**, the **user-triggered, share-extension, single-public-URL** pattern
  is the posture courts have treated **most leniently** — it is user-initiated,
  one item at a time, on public content, not bulk scraping. Relevant precedent
  cited in research: **hiQ v. LinkedIn** and **Meta v. Bright Data** (public-data
  scraping treated far more favorably than authenticated/bulk harvesting).
- This is a **risk posture to confirm with the user/legal**, not a settled green
  light. It is the single biggest non-engineering gate on the project.

---

## 6. Options

### Option 1 — Caption-only (status quo, hardened)
Keep the link lane caption-only; just rely on the already-shipped extraction-first
Gemini pass. No audio from links.
- **Pros:** zero new cost, zero ToS exposure, already done.
- **Cons:** fails on no-caption / thin-caption videos — the exact case the user
  cares about. Does not close the gap.

### Option 2 — Share-extension + server-side single-URL fetch → ASR → Gemini  ✅ RECOMMENDED
Match Recime: when a social item is shared, the **server** fetches the single
public URL, extracts audio, runs **Whisper STT**, then **Gemini** structures it.
Caption → audio → web as a **fallback chain**.
- **Pros:** closes the gap; parity with the category leader; defensible ToS
  posture; reuses the existing `import-from-audio` → Gemini pipeline downstream.
- **Cons:** real multi-part build (server-side media fetch + ASR wiring + share-
  extension changes) and **real recurring cost** (transcription per import).
- **Fast-follow (held back):** OCR / on-frame vision for text baked into the video.

**Recommendation: Option 2**, with OCR/vision as a later fast-follow.

---

## 7. What Option 2 requires (scope sketch — not yet planned)

This is a **multi-part initiative**, not a quick add:

1. **Server-side media fetch** — download the single shared public URL
   (yt-dlp / cobalt-style), extract the audio track. New infra + dependency +
   the ToS decision from §5.
2. **ASR wiring** — feed extracted audio into the existing **Groq Whisper**
   (`import-from-audio`) → **Gemini** structuring path. Downstream of the fetch,
   this pipeline already exists.
3. **Share-extension / client wiring** — route social shares through the new
   server lane; build the caption → audio → web fallback chain so a clean caption
   still short-circuits cheaply.
4. **Cost controls** — likely an import cap and/or paywall tier (cf. Recime's
   ~5/week), because transcription is the expensive operation.

---

## 8. Open decisions before any code (the gate)

1. **ToS risk acceptance** — are we comfortable with user-triggered server-side
   single-URL fetch of public social media? (§5)
2. **Cost model** — what per-import transcription cost is acceptable, and does
   this require an import cap / paywall tier? (§4, §7.4)
3. **Scope of v1** — Option 2 full chain, or a narrower slice first?
4. **Ownership** — user indicated this should be started with a **different
   agent** as its own phase.

---

## 9. Pointers

- Existing pipeline to reuse: `backend/src/services/recipeAudioImportService.ts`
  (`import-from-audio` → Whisper → Gemini), `recipeCleanupService.ts`
  (`extractRecipeFromText`, `cleanupRecipeDraft`), `routes/recipes.ts`.
- Lane detection on iOS: `RecipeImportPendingStore.swift`
  (`prefersBrowserImport=true` for Instagram/TikTok/FB/YouTube/Pinterest);
  caption extraction in `RecipesViews.swift`.
- Related memory: `project_recipe_ui_polish.md` (the UI phase this follows),
  `project_recipes_data_model_plan.md`, `project_build43_testflight.md`
  (STT-vs-Gemini clarification).
