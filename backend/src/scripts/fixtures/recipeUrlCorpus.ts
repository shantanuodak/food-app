/**
 * Recipe URL corpus for parse-quality benchmarking.
 *
 * ~55 real recipe URLs spanning the source types our users actually paste:
 * big aggregators, food-media sites, independent blogs, and international
 * sites. Tagged by `category` so the harness can break down quality by
 * source type (blogs tend to be noisier; institutional sites cleaner).
 *
 * NOTE: TikTok / Instagram / Facebook are deliberately NOT here — those go
 * through the audio-transcription lane (recipeAudioImportService), not URL
 * scraping. Pasting a social URL into the URL importer would just fail. The
 * social lane needs its own fixture set (captions/transcripts) — tracked
 * separately. See recipeQualityHarness.ts header.
 *
 * Some URLs will 403 (bot walls) and fall back to the Jina reader; a few may
 * 404 over time. The harness reports import failures separately from the
 * quality distribution, so dead URLs don't pollute the score signal.
 */

export type CorpusCategory = 'aggregator' | 'media' | 'blog' | 'international' | 'institutional';

export interface CorpusEntry {
  url: string;
  source: string;
  category: CorpusCategory;
}

export const RECIPE_URL_CORPUS: CorpusEntry[] = [
  // ---- Aggregators ----
  { url: 'https://www.allrecipes.com/recipe/39748/spicy-turkey-burgers/', source: 'allrecipes', category: 'aggregator' },
  { url: 'https://www.allrecipes.com/recipe/16354/easy-meatloaf/', source: 'allrecipes', category: 'aggregator' },
  { url: 'https://www.food.com/recipe/the-best-banana-bread-2886', source: 'food.com', category: 'aggregator' },
  { url: 'https://www.epicurious.com/recipes/food/views/classic-pancakes', source: 'epicurious', category: 'aggregator' },
  { url: 'https://www.yummly.com/recipe/Garlic-Butter-Shrimp-9094593', source: 'yummly', category: 'aggregator' },
  { url: 'https://tasty.co/recipe/one-pot-chicken-alfredo', source: 'tasty', category: 'aggregator' },

  // ---- Food media ----
  { url: 'https://www.foodnetwork.com/recipes/tyler-florence/chicken-parmesan-recipe-1951130', source: 'foodnetwork', category: 'media' },
  { url: 'https://www.seriouseats.com/the-best-slow-cooked-bolognese-sauce-recipe', source: 'seriouseats', category: 'media' },
  { url: 'https://www.seriouseats.com/perfect-scrambled-eggs-recipe', source: 'seriouseats', category: 'media' },
  { url: 'https://www.bonappetit.com/recipe/bas-best-chocolate-chip-cookies', source: 'bonappetit', category: 'media' },
  { url: 'https://cooking.nytimes.com/recipes/1018058-creamy-macaroni-and-cheese', source: 'nytcooking', category: 'media' },
  { url: 'https://www.delish.com/cooking/recipe-ideas/a19636089/best-baked-chicken-breast-recipe/', source: 'delish', category: 'media' },
  { url: 'https://www.eatingwell.com/recipe/250709/honey-garlic-chicken-thighs/', source: 'eatingwell', category: 'media' },
  { url: 'https://www.thekitchn.com/how-to-make-a-quiche-cooking-lessons-from-the-kitchn-218209', source: 'thekitchn', category: 'media' },
  { url: 'https://www.tasteofhome.com/recipes/the-best-ever-chili/', source: 'tasteofhome', category: 'media' },
  { url: 'https://www.simplyrecipes.com/recipes/banana_bread/', source: 'simplyrecipes', category: 'media' },
  { url: 'https://www.kingarthurbaking.com/recipes/classic-birthday-cake-recipe', source: 'kingarthur', category: 'media' },

  // ---- Independent blogs ----
  { url: 'https://www.loveandlemons.com/stir-fry-recipe/', source: 'loveandlemons', category: 'blog' },
  { url: 'https://cookieandkate.com/best-lentil-soup-recipe/', source: 'cookieandkate', category: 'blog' },
  { url: 'https://minimalistbaker.com/easy-vegan-ramen/', source: 'minimalistbaker', category: 'blog' },
  { url: 'https://minimalistbaker.com/1-bowl-vegan-banana-bread/', source: 'minimalistbaker', category: 'blog' },
  { url: 'https://www.recipetineats.com/chicken-stir-fry/', source: 'recipetineats', category: 'blog' },
  { url: 'https://www.recipetineats.com/beef-stew/', source: 'recipetineats', category: 'blog' },
  { url: 'https://www.gimmesomeoven.com/baked-chicken-breast/', source: 'gimmesomeoven', category: 'blog' },
  { url: 'https://sallysbakingaddiction.com/best-chocolate-chip-cookies/', source: 'sallysbaking', category: 'blog' },
  { url: 'https://www.budgetbytes.com/dragon-noodles/', source: 'budgetbytes', category: 'blog' },
  { url: 'https://smittenkitchen.com/2019/01/perfect-uncluttered-chicken-stock/', source: 'smittenkitchen', category: 'blog' },
  { url: 'https://www.halfbakedharvest.com/marry-me-chicken/', source: 'halfbakedharvest', category: 'blog' },
  { url: 'https://pinchofyum.com/the-best-soft-chocolate-chip-cookies', source: 'pinchofyum', category: 'blog' },
  { url: 'https://www.skinnytaste.com/baked-chicken-nuggets/', source: 'skinnytaste', category: 'blog' },
  { url: 'https://thewoksoflife.com/kung-pao-chicken/', source: 'thewoksoflife', category: 'blog' },
  { url: 'https://www.ambitiouskitchen.com/best-banana-bread/', source: 'ambitiouskitchen', category: 'blog' },
  { url: 'https://natashaskitchen.com/creamy-garlic-chicken-recipe/', source: 'natashaskitchen', category: 'blog' },
  { url: 'https://www.twopeasandtheirpod.com/easy-guacamole/', source: 'twopeas', category: 'blog' },
  { url: 'https://damndelicious.net/2019/09/06/garlic-butter-steak-bites/', source: 'damndelicious', category: 'blog' },
  { url: 'https://www.spendwithpennies.com/easy-meatloaf-recipe/', source: 'spendwithpennies', category: 'blog' },
  { url: 'https://www.onceuponachef.com/recipes/perfect-basmati-rice.html', source: 'onceuponachef', category: 'blog' },
  { url: 'https://cafedelites.com/honey-garlic-butter-salmon-in-foil/', source: 'cafedelites', category: 'blog' },
  { url: 'https://www.foodiecrush.com/the-best-chicken-noodle-soup-recipe/', source: 'foodiecrush', category: 'blog' },

  // ---- International ----
  { url: 'https://www.bbcgoodfood.com/recipes/best-ever-chocolate-brownies-recipe', source: 'bbcgoodfood', category: 'international' },
  { url: 'https://www.bbcgoodfood.com/recipes/classic-victoria-sandwich-recipe', source: 'bbcgoodfood', category: 'international' },
  { url: 'https://www.bbc.co.uk/food/recipes/spaghetti_bolognese_with_94814', source: 'bbcfood', category: 'international' },
  { url: 'https://www.jamieoliver.com/recipes/chicken-recipes/perfect-roast-chicken/', source: 'jamieoliver', category: 'international' },
  { url: 'https://www.taste.com.au/recipes/spaghetti-bolognese-recipe/zb3rwgu0', source: 'taste.com.au', category: 'international' },
  { url: 'https://www.indianhealthyrecipes.com/paneer-butter-masala/', source: 'indianhealthyrecipes', category: 'international' },
  { url: 'https://www.justonecookbook.com/teriyaki-chicken/', source: 'justonecookbook', category: 'international' },
  { url: 'https://rasamalaysia.com/kung-pao-chicken-recipe/', source: 'rasamalaysia', category: 'international' },
  { url: 'https://www.giallozafferano.com/recipes/Tiramisu-recipe.html', source: 'giallozafferano', category: 'international' },
  { url: 'https://www.maangchi.com/recipe/kimchi-jjigae', source: 'maangchi', category: 'international' },

  // ---- Institutional / structured ----
  { url: 'https://theicn.org/cnrb/recipes-for-child-nutrition-programs/breakfast/breakfast-bowl/', source: 'theicn', category: 'institutional' },
  { url: 'https://www.kingarthurbaking.com/recipes/no-knead-crusty-white-bread-recipe', source: 'kingarthur', category: 'institutional' },
  { url: 'https://www.wholefoodsmarket.com/recipes/simple-roast-chicken', source: 'wholefoods', category: 'institutional' },
];
