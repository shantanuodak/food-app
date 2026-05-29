import 'dotenv/config';
/**
 * Social-lane parse-quality eval (TikTok / Instagram / Facebook).
 *
 * Social recipes don't go through URL scraping — they're video → audio →
 * Whisper transcript → buildRecipeDraftFromTranscript (a heuristic extractor).
 * That transcript is the noisiest input we get: stream-of-consciousness
 * narration, "follow for part 2", hashtags, emoji, vague quantities ("a good
 * amount of olive oil"), zero metadata.
 *
 * This eval feeds realistic fixture TRANSCRIPTS straight into the real social
 * extractor (no Groq needed), scores the raw draft, runs the SAME Gemini
 * cleanup pass we built for the web lane, and scores the cleaned draft. It
 * measures two things at once:
 *   1. How often the deterministic extractor even produces a draft from a
 *      social transcript (it throws if it can't find ingredients).
 *   2. How much the cleanup pass lifts the ones it does produce.
 *
 * Usage: npm run recipe:social-compare    (requires GEMINI_API_KEY)
 */

import { buildRecipeDraftFromTranscript } from '../services/recipeAudioImportService.js';
import { cleanupRecipeDraft } from '../services/recipeCleanupService.js';
import { scoreRecipeDraft } from '../services/recipeQualityScore.js';

interface Fixture {
  name: string;
  platform: string;
  sourceUrl: string;
  sourceName: string;
  transcript: string;
}

const FIXTURES: Fixture[] = [
  {
    name: 'TikTok ramble — baked feta pasta',
    platform: 'tiktok',
    sourceUrl: 'https://www.tiktok.com/@chef/video/1001',
    sourceName: 'TikTok',
    transcript:
      "okay you guys so today we're making the viral baked feta pasta trust me it's so good okay so what you're gonna need is one block of feta cheese a pint of cherry tomatoes like a good amount of olive oil just drizzle it don't be shy some garlic like four cloves salt and pepper and a box of pasta whatever you have. okay so first preheat your oven to 400 degrees then you put the feta in the middle of a baking dish and surround it with the tomatoes drizzle everything with the olive oil and add your garlic bake it for like 35 minutes until everything is all roasty then meanwhile cook your pasta okay don't forget to save the pasta water then you mash everything together add the pasta and mix it up it's so creamy you guys. okay follow me for part two where I show you the leftovers #fyp #pasta #viral",
  },
  {
    name: 'Instagram caption — tuscan chicken',
    platform: 'instagram',
    sourceUrl: 'https://www.instagram.com/reel/abc123/',
    sourceName: 'Instagram',
    transcript:
      "🔥THE BEST creamy tuscan chicken🔥 save this for later!! 😍\n\nyou'll need 👇\n2 chicken breasts\n1 cup heavy cream\n1/2 cup sun dried tomatoes\n2 cups spinach\n3 cloves garlic\nparmesan obvi 🧀\n\nseason the chicken & sear it til golden ✨ remove it then in the same pan add garlic + sundried tomatoes, pour in the cream, throw in the spinach til wilted, add parm, put the chicken back & simmer 🤤 SO good over pasta!!\n\nfollow @chef for more 💕 #tuscanchicken #dinnerideas #easyrecipes #reels",
  },
  {
    name: 'Facebook chatty — banana bread',
    platform: 'facebook',
    sourceUrl: 'https://www.facebook.com/watch/?v=2002',
    sourceName: 'Facebook',
    transcript:
      "Hi everyone welcome back to my kitchen, if you enjoy these videos please give it a like and share it with your friends it really helps. Today I'm making my famous banana bread. You're going to need three ripe bananas, two cups of flour, one cup of sugar, half a cup of melted butter, two eggs, one teaspoon of baking soda, and a pinch of salt. So first you mash the bananas in a big bowl, then you mix in the melted butter, add the sugar the eggs and the baking soda and salt, then you fold in the flour, don't overmix it now. Pour it into a greased loaf pan and bake at 350 for about an hour. Let it cool. Enjoy! And don't forget to subscribe.",
  },
  {
    name: 'TikTok well-narrated — stir fry (control)',
    platform: 'tiktok',
    sourceUrl: 'https://www.tiktok.com/@chef/video/1004',
    sourceName: 'TikTok',
    transcript:
      "In this video I'll show you a quick weeknight stir fry. Ingredients: one pound of chicken thighs sliced thin, two tablespoons of soy sauce, one tablespoon of sesame oil, three cloves of garlic minced, and two cups of broccoli florets. First, heat the sesame oil in a large skillet over medium high heat. Add the chicken and cook until browned, about five minutes. Stir in the garlic and broccoli and cook for four minutes. Pour in the soy sauce, toss to coat, and serve hot over rice.",
  },
  {
    name: 'Viral vague — no real quantities',
    platform: 'tiktok',
    sourceUrl: 'https://www.tiktok.com/@chef/video/1005',
    sourceName: 'TikTok',
    transcript:
      "ok this broke the internet so you have to try it. grab a block of feta, a whole bunch of cherry tomatoes, a ton of olive oil like just pour it, some garlic, and pasta. dump it all in a dish, bake it til it's bubbly, then smush it together with the pasta. that's it. it's insane. like and follow for more lazy dinners",
  },
  {
    name: 'Banter-heavy — garlic butter shrimp',
    platform: 'youtube',
    sourceUrl: 'https://www.tiktok.com/@jake/video/1006',
    sourceName: 'TikTok',
    transcript:
      "what is up everybody welcome back to the channel if you're new here my name is Jake and I make easy recipes hit that subscribe button. so today a lot of you have been asking for my garlic butter shrimp so let's get into it. okay so for this you're gonna need one pound of shrimp peeled and deveined, four tablespoons of butter, five cloves of garlic minced, juice of one lemon, and some parsley. melt the butter in a pan, add the garlic cook till fragrant, throw in the shrimp cook two minutes per side, squeeze the lemon, sprinkle the parsley, done. so easy right. let me know in the comments what I should make next and I'll see you guys next time peace.",
  },
];

async function main() {
  console.log('Social-lane eval — transcript → raw extractor → Gemini cleanup\n');
  console.log('  RAW → CLN   Δ   | PLATFORM   | FIXTURE');
  console.log('  ' + '─'.repeat(80));

  const deltas: number[] = [];
  let extractorFailures = 0;
  const resolvedCounts = new Map<string, number>();
  const introducedCounts = new Map<string, number>();

  for (const fx of FIXTURES) {
    let raw;
    try {
      raw = buildRecipeDraftFromTranscript({
        transcript: fx.transcript,
        sourceUrl: fx.sourceUrl,
        sourceName: fx.sourceName,
      });
    } catch (err) {
      extractorFailures += 1;
      const code = (err as { code?: string })?.code ?? String(err).slice(0, 40);
      console.log(`  EXTRACTOR FAILED (${code}) | ${fx.platform.padEnd(10)} | ${fx.name}`);
      continue;
    }

    const before = scoreRecipeDraft(raw);
    const { cleaned, changed, skippedReason } = await cleanupRecipeDraft(raw);
    const after = scoreRecipeDraft(cleaned);
    const delta = after.overall - before.overall;
    deltas.push(delta);

    const beforeCodes = new Set(before.defects.map((d) => d.code));
    const afterCodes = new Set(after.defects.map((d) => d.code));
    const resolved = [...beforeCodes].filter((c) => !afterCodes.has(c));
    const introduced = [...afterCodes].filter((c) => !beforeCodes.has(c));
    for (const c of resolved) resolvedCounts.set(c, (resolvedCounts.get(c) ?? 0) + 1);
    for (const c of introduced) introducedCounts.set(c, (introducedCounts.get(c) ?? 0) + 1);

    const arrow = delta > 0 ? '▲' : delta < 0 ? '▼' : '=';
    const note = changed ? '' : ` [SKIPPED:${skippedReason}]`;
    console.log(`  ${String(before.overall).padStart(3)} → ${String(after.overall).padStart(3)}  ${arrow}${String(Math.abs(delta)).padStart(3)} | ${fx.platform.padEnd(10)} | ${fx.name}${note}`);
    console.log(`                       raw band ${before.band} → cleaned ${after.band}`);
    if (resolved.length) console.log(`                       resolved: ${resolved.join(', ')}`);
    if (introduced.length) console.log(`                       ⚠ introduced: ${introduced.join(', ')}`);
  }

  const mean = deltas.length ? deltas.reduce((a, b) => a + b, 0) / deltas.length : 0;
  console.log('\n──────────── SOCIAL SUMMARY ────────────');
  console.log(`Fixtures:              ${FIXTURES.length}`);
  console.log(`Extractor produced a draft: ${FIXTURES.length - extractorFailures}/${FIXTURES.length}`);
  console.log(`Extractor failures:    ${extractorFailures}`);
  console.log(`Mean cleanup delta:    ${mean >= 0 ? '+' : ''}${mean.toFixed(1)} (over drafts that extracted)`);
  if (resolvedCounts.size) {
    console.log('\nDefects resolved by cleanup:');
    for (const [c, n] of [...resolvedCounts.entries()].sort((a, b) => b[1] - a[1])) console.log(`  ${String(n).padStart(2)}  ${c}`);
  }
  if (introducedCounts.size) {
    console.log('\nDefects introduced (watch list):');
    for (const [c, n] of [...introducedCounts.entries()].sort((a, b) => b[1] - a[1])) console.log(`  ${String(n).padStart(2)}  ${c}`);
  }
}

main().catch((err) => { console.error('Social eval crashed:', err); process.exit(1); });
