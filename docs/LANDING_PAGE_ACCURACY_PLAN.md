# Food App Landing Page and Accuracy Benchmark Plan

Created: 2026-05-10

## Purpose

Create a public-facing Food App website that explains what the app does, why the AI estimates can be trusted, what is coming next, and how users can download or join the product.

The page should not feel like a generic AI calorie tracker landing page. The strongest positioning is:

- fast natural-language food logging
- transparent nutrition estimation
- practical confidence without overwhelming users
- visible product momentum through roadmap, bug fixes, and upcoming features

## Recommended Site Structure

### 1. Hero

Goal: make the product obvious in the first viewport.

Content:

- Headline: Food App
- Supporting copy: Log meals in plain language and get practical calories and macros in seconds.
- Primary CTA: Download Food App
- Secondary CTA: See Accuracy
- Visual: app screen showing a meal typed naturally and converted into calories/macros.

Notes:

- Use real app UI screenshots or high-quality generated device mockups.
- Avoid vague AI imagery. The user should immediately understand the product.

### 2. How It Works

Goal: explain the loop simply.

Steps:

1. Type what you ate.
2. Food App parses the meal.
3. Food App estimates calories and macros.
4. You can review, adjust, and save.

Keep this short. This section is about comprehension, not deep technical trust.

### 3. Accuracy and Trust

Goal: make users confident without showing internal match confidence.

Content:

- Explain that Food App estimates nutrition by matching the user entry to common foods, serving sizes, and known nutrition references.
- Explain that results are estimates, not medical-grade measurements.
- Show a clear accuracy benchmark summary:
  - Overall score
  - Tests passed
  - Last updated date
  - Category scores

Recommended categories:

- Simple foods
- Restaurant and branded foods
- Homemade meals
- Indian and international foods
- Typos and messy inputs
- Portion-specific foods
- Ambiguous entries

### 4. Benchmark Table

Goal: show proof, not just claims.

Compare Food App against trusted reference values, not primarily against competitors.

Reference sources:

- USDA FoodData Central for simple foods
- Official restaurant nutrition pages for chain/brand items
- Curated recipe calculations for homemade meals
- Curated real-world test cases for typos, ambiguous meals, and common user phrases

Suggested columns:

- Test input
- Reference calories
- Food App calories
- Difference
- Macro score
- Result: Strong, Reasonable, Needs review
- Short note

Scoring formula:

```text
Overall score =
40% calories accuracy
25% protein accuracy
20% carbs accuracy
15% fat accuracy
```

This formula can be adjusted later, but the public page and dashboard should use the same scoring logic.

### 5. Explanation Example

Goal: replace hidden match confidence with user-readable reasoning.

Use the same tone as the in-app drawer heading:

> How Food App Estimated This

Example copy:

> Food App interpreted "one bowl dal rice" as a mixed serving of cooked lentils and cooked rice. The estimate uses a practical bowl-size serving and common nutrition values for homemade dal and white rice. Since homemade recipes vary by oil, lentil ratio, and portion size, this estimate is best treated as a close logging estimate rather than an exact measurement.

Guidelines:

- concise but specific
- no chain-of-thought
- mention the interpreted food
- mention serving assumption
- mention the reference basis
- mention uncertainty only when useful

### 6. Roadmap

Goal: show product momentum.

Pull from the same CMS-style roadmap pipeline used by the app and testing dashboard.

Sections:

- Upcoming fixes
- Upcoming features

Fields:

- Title
- Description
- Status: Not started, In progress, Done
- Release number
- Target date or TBD

This should mirror the app manager account roadmap screen and the nutrition testing dashboard.

### 7. Feedback Loop

Goal: show users that feedback turns into product work.

Explain the pipeline:

1. User submits feedback in the app.
2. Feedback appears in the nutrition testing dashboard.
3. Admin classifies it as a bug report or feature request.
4. Admin promotes it into the roadmap.
5. Roadmap item appears in the app and website.

This becomes a strong trust signal: the product is actively maintained and user feedback matters.

### 8. Pricing / Availability

Goal: keep the business model clear.

Add later when pricing is final.

Potential sections:

- Free trial
- Monthly plan
- Annual plan
- What is included

### 9. FAQ

Recommended questions:

- How accurate is Food App?
- Where do nutrition estimates come from?
- Can I edit a result?
- Does Food App work for Indian food?
- Does Food App work with restaurant food?
- Is this medical advice?
- Does Food App sync with Apple Health?

## Dashboard Work To Add

This accuracy concept should be added to the nutrition testing dashboard before the public website.

Recommended dashboard additions:

### Accuracy Benchmark Tab

Purpose:

- manage benchmark test cases
- run parser against cases
- compare output to reference values
- produce score summaries for internal review and public display

Fields:

- test input
- category
- reference source
- reference calories
- reference protein
- reference carbs
- reference fat
- expected serving note
- Food App calories/protein/carbs/fat
- score
- status
- last run date
- parser version or prompt version

### Public Snapshot

Purpose:

- allow admin to choose which benchmark run is public
- prevent unstable internal experiments from automatically showing on the website

Fields:

- benchmark run id
- public title
- public summary
- published score
- published at
- visible categories

## Confidence Recommendation

Do not rush confidence back into the user-facing UI right now.

The better immediate move is:

1. Keep match confidence hidden from normal users.
2. Improve the explanation quality in the food drawer.
3. Add benchmark scoring and confidence diagnostics to the testing dashboard.
4. Use internal confidence to help decide which parses need review, not as a raw number shown to users.

Why:

- A raw confidence score can make users less confident if they do not know how to interpret it.
- The user mostly needs to know "can I trust this enough to log it?"
- A clear explanation plus editable result is more helpful than a decimal score.
- The testing dashboard still needs confidence because it helps debug parser quality, prompt changes, and bad matches.

Recommended dashboard confidence fields:

- match confidence
- serving confidence
- food identity confidence
- macro confidence
- explanation quality score
- source quality: USDA, official restaurant, cached parse, AI estimate, unknown

Later, the app can show a simple user-facing label instead of a number:

- Strong estimate
- Reasonable estimate
- Review portion

## Phased Implementation Plan

### Phase 1: Internal Accuracy Dashboard

- Add benchmark case storage.
- Add dashboard tab to create/edit benchmark cases.
- Add run button to parse cases through current parser.
- Compare parser output to reference values.
- Store score by category and macro.

### Phase 2: Explanation Quality

- Improve prompt instructions for concise, confidence-building explanations.
- Add testing dashboard review for explanations.
- Track whether explanations mention food interpretation, serving assumption, and source basis.

### Phase 3: Public Snapshot API

- Add backend route for published benchmark summary.
- Admin chooses which benchmark run is public.
- Website can consume a stable public snapshot.

### Phase 4: Landing Page

- Build public landing page.
- Add hero, how it works, accuracy benchmark, roadmap, feedback loop, FAQ, and download CTA.
- Use real app UI screenshots.

### Phase 5: Competitive Comparison

- Optional later.
- Compare Food App against MyFitnessPal, Cronometer, Amy, or other tools only after Food App has an objective reference benchmark.

## Decision

Confidence should be worked on now in the testing dashboard, but not rushed into the app UI or public website.

The public/user-facing layer should focus on clear explanations and benchmark proof. The internal dashboard should keep the deeper confidence diagnostics so we can improve quality safely before exposing any simplified trust labels to users.
