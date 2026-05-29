import { afterEach, describe, expect, test, vi } from 'vitest';

const baseEnv = { ...process.env };

afterEach(() => {
  vi.resetModules();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  process.env = { ...baseEnv };
});

function useTestDatabaseUrl() {
  process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/food_app_test';
}

describe('recipeImportService URL safety', () => {
  test('accepts public http and https recipe URLs', async () => {
    useTestDatabaseUrl();
    const { assertSafeRecipeUrl } = await import('../src/services/recipeImportService.js');

    expect(assertSafeRecipeUrl('https://www.example.com/recipes/toast#comments')).toEqual({
      url: 'https://www.example.com/recipes/toast',
      domain: 'example.com'
    });
    expect(assertSafeRecipeUrl('http://recipes.example.com/toast')).toEqual({
      url: 'http://recipes.example.com/toast',
      domain: 'recipes.example.com'
    });
  });

  test('rejects non-http, localhost, and private-network URLs', async () => {
    useTestDatabaseUrl();
    const { assertSafeRecipeUrl } = await import('../src/services/recipeImportService.js');

    for (const url of [
      'file:///etc/passwd',
      'ftp://example.com/recipe',
      'http://localhost:3000/recipe',
      'http://127.0.0.1/recipe',
      'http://10.0.0.5/recipe',
      'http://172.20.0.5/recipe',
      'http://192.168.1.5/recipe',
      'http://169.254.1.5/recipe',
      'http://[::1]/recipe',
      'http://printer.local/recipe'
    ]) {
      expect(() => assertSafeRecipeUrl(url), url).toThrow();
    }
  });
});

describe('recipeImportService.assertResolvedHostIsPublic (SSRF DNS guard)', () => {
  test('allows a host that resolves only to public addresses', async () => {
    useTestDatabaseUrl();
    const { assertResolvedHostIsPublic } = await import('../src/services/recipeImportService.js');
    const resolver = async () => [{ address: '93.184.216.34', family: 4 }];
    await expect(assertResolvedHostIsPublic('example.com', resolver)).resolves.toBeUndefined();
  });

  test('rejects a host that resolves to an internal/metadata address (DNS rebinding)', async () => {
    useTestDatabaseUrl();
    const { assertResolvedHostIsPublic } = await import('../src/services/recipeImportService.js');
    const cases: Array<Array<{ address: string; family: number }>> = [
      [{ address: '169.254.169.254', family: 4 }], // cloud metadata endpoint
      [{ address: '10.0.0.5', family: 4 }],
      [{ address: '127.0.0.1', family: 4 }],
      [{ address: '192.168.1.10', family: 4 }],
      [{ address: '172.16.4.4', family: 4 }],
      [{ address: '::1', family: 6 }],
      [{ address: 'fd00::1', family: 6 }],
      // A public + a private record together must STILL reject.
      [{ address: '93.184.216.34', family: 4 }, { address: '169.254.169.254', family: 4 }]
    ];
    for (const records of cases) {
      const resolver = async () => records;
      await expect(
        assertResolvedHostIsPublic('rebinding.example', resolver),
        JSON.stringify(records)
      ).rejects.toThrow();
    }
  });

  test('skips resolution for literal IPs (already validated upstream)', async () => {
    useTestDatabaseUrl();
    const { assertResolvedHostIsPublic } = await import('../src/services/recipeImportService.js');
    let resolverCalled = false;
    const resolver = async () => {
      resolverCalled = true;
      return [{ address: '10.0.0.1', family: 4 }];
    };
    await expect(assertResolvedHostIsPublic('93.184.216.34', resolver)).resolves.toBeUndefined();
    expect(resolverCalled).toBe(false);
  });

  test('rejects when the host cannot be resolved', async () => {
    useTestDatabaseUrl();
    const { assertResolvedHostIsPublic } = await import('../src/services/recipeImportService.js');
    const resolver = async () => {
      throw new Error('ENOTFOUND');
    };
    await expect(assertResolvedHostIsPublic('does-not-exist.example', resolver)).rejects.toThrow();
  });
});

describe('recipeImportRateLimiterService', () => {
  test('allows up to the per-lane limit, then blocks with a retry hint', async () => {
    useTestDatabaseUrl();
    const { checkRecipeImportRateLimit } = await import('../src/services/recipeImportRateLimiterService.js');
    const { config } = await import('../src/config.js');
    const now = 1_000_000;
    const max = config.recipeAudioImportRateLimitMax;
    for (let i = 0; i < max; i += 1) {
      expect(checkRecipeImportRateLimit('user-1', 'audio', now).allowed, `request ${i}`).toBe(true);
    }
    const blocked = checkRecipeImportRateLimit('user-1', 'audio', now);
    expect(blocked.allowed).toBe(false);
    expect(blocked.retryAfterSeconds).toBeGreaterThan(0);
  });

  test('lanes and users have independent budgets', async () => {
    useTestDatabaseUrl();
    const { checkRecipeImportRateLimit } = await import('../src/services/recipeImportRateLimiterService.js');
    const { config } = await import('../src/config.js');
    const now = 2_000_000;
    for (let i = 0; i < config.recipeAudioImportRateLimitMax; i += 1) {
      checkRecipeImportRateLimit('user-2', 'audio', now);
    }
    expect(checkRecipeImportRateLimit('user-2', 'audio', now).allowed).toBe(false);
    // Different lane and different user are unaffected.
    expect(checkRecipeImportRateLimit('user-2', 'url', now).allowed).toBe(true);
    expect(checkRecipeImportRateLimit('user-3', 'audio', now).allowed).toBe(true);
  });

  test('resets after the window elapses', async () => {
    useTestDatabaseUrl();
    const { checkRecipeImportRateLimit } = await import('../src/services/recipeImportRateLimiterService.js');
    const { config } = await import('../src/config.js');
    const now = 3_000_000;
    for (let i = 0; i < config.recipeAudioImportRateLimitMax; i += 1) {
      checkRecipeImportRateLimit('user-4', 'audio', now);
    }
    expect(checkRecipeImportRateLimit('user-4', 'audio', now).allowed).toBe(false);
    const afterWindow = now + config.recipeRateLimitWindowMs + 1_000;
    expect(checkRecipeImportRateLimit('user-4', 'audio', afterWindow).allowed).toBe(true);
  });
});

describe('recipeImportService.readBodyWithByteCap', () => {
  test('returns the full body when under the byte cap', async () => {
    useTestDatabaseUrl();
    const { readBodyWithByteCap } = await import('../src/services/recipeImportService.js');
    const result = await readBodyWithByteCap(new Response('hello world'), 1000, new AbortController());
    expect(result).toBe('hello world');
  });

  test('throws 413 and aborts the request when the body exceeds the cap', async () => {
    useTestDatabaseUrl();
    const { readBodyWithByteCap } = await import('../src/services/recipeImportService.js');
    const controller = new AbortController();
    await expect(
      readBodyWithByteCap(new Response('this body is far too large for the tiny cap'), 5, controller)
    ).rejects.toThrow();
    expect(controller.signal.aborted).toBe(true);
  });

  test('caps on BYTES, not UTF-16 code units (multi-byte safety)', async () => {
    useTestDatabaseUrl();
    const { readBodyWithByteCap } = await import('../src/services/recipeImportService.js');
    // Each pizza emoji is 4 UTF-8 bytes (2 UTF-16 code units); 3 => 12 bytes > 8.
    await expect(
      readBodyWithByteCap(new Response('🍕🍕🍕'), 8, new AbortController())
    ).rejects.toThrow();
  });
});

describe('recipeImportService.buildRecipeDraft', () => {
  test('normalizes scraper output into a reviewable draft', async () => {
    useTestDatabaseUrl();
    const { buildRecipeDraft } = await import('../src/services/recipeImportService.js');

    const draft = buildRecipeDraft(
      {
        name: '  Tomato Toast  ',
        image: 'https://cdn.example.com/toast.jpg',
        description: 'Simple tomato toast',
        recipeYield: '2 servings',
        prepTime: '5 minutes',
        recipeIngredients: [' 2 slices bread ', '1 tomato', '1 tomato'],
        recipeInstructions: ['Toast bread', 'Top with tomato'],
        recipeCategories: ['Breakfast', 'Breakfast'],
        recipeCuisines: ['Italian'],
        keywords: ['toast', 'quick']
      },
      'https://www.example.com/recipes/tomato-toast'
    );

    expect(draft).toMatchObject({
      title: 'Tomato Toast',
      sourceUrl: 'https://www.example.com/recipes/tomato-toast',
      sourceDomain: 'example.com',
      sourceName: 'example.com',
      heroImageUrl: 'https://cdn.example.com/toast.jpg',
      servings: '2 servings',
      prepTime: '5 minutes',
      categories: ['Breakfast'],
      cuisines: ['Italian'],
      keywords: ['toast', 'quick'],
      confidence: 0.92,
      warnings: []
    });
    expect(draft.ingredients.map((ingredient) => ingredient.rawText)).toEqual(['2 slices bread', '1 tomato']);
    expect(draft.steps.map((step) => step.text)).toEqual(['Toast bread', 'Top with tomato']);
  });

  test('rejects scraper output without title or ingredients', async () => {
    useTestDatabaseUrl();
    const { buildRecipeDraft } = await import('../src/services/recipeImportService.js');

    expect(() =>
      buildRecipeDraft({ name: 'No ingredients', recipeIngredients: [] }, 'https://example.com/recipe')
    ).toThrow(expect.objectContaining({ code: 'RECIPE_IMPORT_INCOMPLETE_RECIPE' }));
  });

  test('normalizes malformed scraper image URLs without blocking import', async () => {
    useTestDatabaseUrl();
    const { buildRecipeDraft } = await import('../src/services/recipeImportService.js');

    const draft = buildRecipeDraft(
      {
        name: 'Turkey Burgers',
        image: 'https://cdn.example.com/turkey-burgers.jpg)](https://www.example.com/recipe#',
        recipeIngredients: ['1 pound turkey'],
        recipeInstructions: ['Cook burgers.']
      },
      'https://www.example.com/recipes/turkey-burgers'
    );

    expect(draft.heroImageUrl).toBe('https://cdn.example.com/turkey-burgers.jpg');
  });
});

describe('recipeImportService.importRecipeFromUrl', () => {
  test('uses the installed scraper to extract JSON-LD recipe data', async () => {
    useTestDatabaseUrl();

    const query = vi
      .fn()
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [{ id: '99999999-9999-9999-9999-999999999998' }] })
      .mockResolvedValueOnce({ rows: [] });
    const release = vi.fn();
    const html = `
      <html>
        <head>
          <script type="application/ld+json">
            {
              "@context": "https://schema.org",
              "@type": "Recipe",
              "name": "Classic Tomato Toast",
              "recipeYield": 4,
              "recipeIngredient": [
                "2 slices sourdough",
                "1 ripe tomato"
              ],
              "recipeInstructions": [
                { "@type": "HowToStep", "text": "Toast the bread." },
                { "@type": "HowToStep", "text": "Add tomato and salt." }
              ]
            }
          </script>
        </head>
      </html>
    `;

    vi.stubGlobal(
      'fetch',
      vi.fn(async () => new Response(html, { status: 200, headers: { 'content-type': 'text/html' } }))
    );
    vi.doMock('../src/db.js', () => ({
      pool: {
        connect: vi.fn(async () => ({ query, release }))
      }
    }));
    vi.doMock('../src/services/userService.js', () => ({
      ensureUserExists: vi.fn(async () => undefined)
    }));

    const { importRecipeFromUrl, setRecipeHostResolverForTests } = await import('../src/services/recipeImportService.js');
    setRecipeHostResolverForTests(async () => [{ address: '93.184.216.34', family: 4 }]);

    await expect(
      importRecipeFromUrl({
        userId: '11111111-1111-1111-1111-111111111111',
        auth: { authProvider: 'dev', userEmail: 'user@example.com' },
        url: 'https://www.example.com/recipes/classic-tomato-toast'
      })
    ).resolves.toMatchObject({
      importId: '99999999-9999-9999-9999-999999999998',
      draft: {
        title: 'Classic Tomato Toast',
        servings: '4',
        ingredients: [{ rawText: '2 slices sourdough' }, { rawText: '1 ripe tomato' }],
        steps: [{ text: 'Toast the bread.' }, { text: 'Add tomato and salt.' }]
      }
    });
  });

  test('fetches HTML safely, scrapes deterministically, and stores an import draft', async () => {
    useTestDatabaseUrl();

    const scraper = vi.fn(async () => ({
      name: 'Tomato Toast',
      recipeIngredients: ['2 slices bread', '1 tomato'],
      recipeInstructions: ['Toast bread']
    }));
    const query = vi
      .fn()
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [{ id: '99999999-9999-9999-9999-999999999999' }] })
      .mockResolvedValueOnce({ rows: [] });
    const release = vi.fn();
    const fetchMock = vi.fn(async () => {
      return new Response('<html><script type="application/ld+json">{}</script></html>', {
        status: 200,
        headers: { 'content-type': 'text/html; charset=utf-8' }
      });
    });

    vi.stubGlobal('fetch', fetchMock);
    vi.doMock('@dimfu/recipe-scraper', () => ({ default: scraper }));
    vi.doMock('../src/db.js', () => ({
      pool: {
        connect: vi.fn(async () => ({ query, release }))
      }
    }));
    vi.doMock('../src/services/userService.js', () => ({
      ensureUserExists: vi.fn(async () => undefined)
    }));

    const { importRecipeFromUrl, setRecipeHostResolverForTests } = await import('../src/services/recipeImportService.js');
    setRecipeHostResolverForTests(async () => [{ address: '93.184.216.34', family: 4 }]);

    await expect(
      importRecipeFromUrl({
        userId: '11111111-1111-1111-1111-111111111111',
        auth: { authProvider: 'dev', userEmail: 'user@example.com' },
        url: 'https://www.example.com/recipes/tomato-toast'
      })
    ).resolves.toMatchObject({
      importId: '99999999-9999-9999-9999-999999999999',
      draft: {
        title: 'Tomato Toast',
        sourceDomain: 'example.com',
        ingredients: [{ rawText: '2 slices bread' }, { rawText: '1 tomato' }],
        steps: [{ text: 'Toast bread' }]
      }
    });

    expect(fetchMock).toHaveBeenCalledWith(
      'https://www.example.com/recipes/tomato-toast',
      expect.objectContaining({ redirect: 'manual' })
    );
    expect(scraper).toHaveBeenCalledWith({ html: '<html><script type="application/ld+json">{}</script></html>' });
    expect(query).toHaveBeenNthCalledWith(1, 'BEGIN');
    expect(query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('INSERT INTO recipe_imports'),
      expect.arrayContaining(['11111111-1111-1111-1111-111111111111', 'https://www.example.com/recipes/tomato-toast', 'example.com'])
    );
    expect(query).toHaveBeenNthCalledWith(3, 'COMMIT');
    expect(release).toHaveBeenCalledTimes(1);
  });

  test('falls back to reader markdown when the recipe page blocks direct fetches', async () => {
    useTestDatabaseUrl();

    const query = vi
      .fn()
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [{ id: '99999999-9999-9999-9999-999999999997' }] })
      .mockResolvedValueOnce({ rows: [] });
    const release = vi.fn();
    const markdown = `
      Title: Best Turkey Burgers

      URL Source: http://www.allrecipes.com/recipe/39748/actually-delicious-turkey-burgers/

      Markdown Content:
      # Best Turkey Burgers Recipe

      This turkey burger recipe is full of flavor and can be used for burgers, meatballs, or meatloaves.

      Prep Time:
      15 mins

      Cook Time:
      15 mins

      Total Time:
      30 mins

      Servings:
      12

      ## Ingredients

      *   3 pounds ground turkey
      *   1 teaspoon salt

      ## Directions

      1.   Gather all ingredients.
      2.   Mix ground turkey and salt together in a large bowl.
    `;
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.startsWith('https://r.jina.ai/http://')) {
        return new Response(markdown, { status: 200, headers: { 'content-type': 'text/plain' } });
      }
      return new Response('blocked', { status: 403, headers: { 'content-type': 'text/html' } });
    });

    vi.stubGlobal('fetch', fetchMock);
    vi.doMock('../src/db.js', () => ({
      pool: {
        connect: vi.fn(async () => ({ query, release }))
      }
    }));
    vi.doMock('../src/services/userService.js', () => ({
      ensureUserExists: vi.fn(async () => undefined)
    }));

    const { importRecipeFromUrl, setRecipeHostResolverForTests } = await import('../src/services/recipeImportService.js');
    setRecipeHostResolverForTests(async () => [{ address: '93.184.216.34', family: 4 }]);

    await expect(
      importRecipeFromUrl({
        userId: '11111111-1111-1111-1111-111111111111',
        auth: { authProvider: 'dev', userEmail: 'user@example.com' },
        url: 'https://www.allrecipes.com/recipe/39748/actually-delicious-turkey-burgers/'
      })
    ).resolves.toMatchObject({
      importId: '99999999-9999-9999-9999-999999999997',
      draft: {
        title: 'Best Turkey Burgers',
        sourceUrl: 'https://www.allrecipes.com/recipe/39748/actually-delicious-turkey-burgers/',
        sourceDomain: 'allrecipes.com',
        servings: '12',
        prepTime: '15 mins',
        cookTime: '15 mins',
        totalTime: '30 mins',
        ingredients: [{ rawText: '3 pounds ground turkey' }, { rawText: '1 teaspoon salt' }],
        steps: [{ text: 'Gather all ingredients.' }, { text: 'Mix ground turkey and salt together in a large bowl.' }]
      }
    });

    expect(fetchMock).toHaveBeenNthCalledWith(
      1,
      'https://www.allrecipes.com/recipe/39748/actually-delicious-turkey-burgers/',
      expect.objectContaining({ redirect: 'manual' })
    );
    expect(fetchMock).toHaveBeenNthCalledWith(
      2,
      'https://r.jina.ai/http://www.allrecipes.com/recipe/39748/actually-delicious-turkey-burgers/',
      expect.objectContaining({ redirect: 'follow' })
    );
    expect(query).toHaveBeenNthCalledWith(1, 'BEGIN');
    expect(query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('INSERT INTO recipe_imports'),
      expect.arrayContaining([
        '11111111-1111-1111-1111-111111111111',
        'https://www.allrecipes.com/recipe/39748/actually-delicious-turkey-burgers/',
        'allrecipes.com'
      ])
    );
    expect(query).toHaveBeenNthCalledWith(3, 'COMMIT');
    expect(release).toHaveBeenCalledTimes(1);
  });

  test('falls back to reader markdown when structured recipe data is missing', async () => {
    useTestDatabaseUrl();

    const query = vi
      .fn()
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [{ id: '99999999-9999-9999-9999-999999999996' }] })
      .mockResolvedValueOnce({ rows: [] });
    const release = vi.fn();
    const markdown = `
      Title: Easy Veggie Stir Fry

      URL Source: http://www.loveandlemons.com/stir-fry-recipe/

      Markdown Content:
      This easy stir fry recipe features colorful veggies in a delicious sweet and savory sauce.

      ## Easy Stir Fry Recipe

      Prep Time: 10 minutes

      Cook Time: 10 minutes

      Total Time: 20 minutes

      Serves 4 to 6

      This vegetable stir fry recipe is a quick, easy, and delicious weeknight dinner!

      *   2 tablespoons[extra-virgin olive oil](https://example.com/oil)
      *   1 red bell pepper, stemmed, seeded, and sliced
      *   3 cups small broccoli florets

      #### **Stir Fry Sauce**

      *   ½ cup water
      *   ⅓ cup[low-sodium soy sauce](https://example.com/soy)
      *   2[garlic cloves](https://example.com/garlic), grated

      Cook Mode Prevent your screen from going dark

      *   Make the stir fry sauce: In a medium bowl, whisk together the water, soy sauce, garlic, and ginger.
      *   Make the stir fry. Heat the olive oil in a large skillet or wok over high heat.
      *   Reduce the heat to medium and pour in the stir fry sauce.
    `;
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.startsWith('https://r.jina.ai/http://')) {
        return new Response(markdown, { status: 200, headers: { 'content-type': 'text/plain' } });
      }
      return new Response('<html><title>Easy Veggie Stir Fry</title></html>', {
        status: 200,
        headers: { 'content-type': 'text/html' }
      });
    });
    const scraper = vi.fn(async () => {
      throw new Error('No recipe found');
    });

    vi.stubGlobal('fetch', fetchMock);
    vi.doMock('@dimfu/recipe-scraper', () => ({ default: scraper }));
    vi.doMock('../src/db.js', () => ({
      pool: {
        connect: vi.fn(async () => ({ query, release }))
      }
    }));
    vi.doMock('../src/services/userService.js', () => ({
      ensureUserExists: vi.fn(async () => undefined)
    }));

    const { importRecipeFromUrl, setRecipeHostResolverForTests } = await import('../src/services/recipeImportService.js');
    setRecipeHostResolverForTests(async () => [{ address: '93.184.216.34', family: 4 }]);

    await expect(
      importRecipeFromUrl({
        userId: '11111111-1111-1111-1111-111111111111',
        auth: { authProvider: 'dev', userEmail: 'user@example.com' },
        url: 'https://www.loveandlemons.com/stir-fry-recipe/'
      })
    ).resolves.toMatchObject({
      importId: '99999999-9999-9999-9999-999999999996',
      draft: {
        title: 'Easy Veggie Stir Fry',
        sourceUrl: 'https://www.loveandlemons.com/stir-fry-recipe/',
        sourceDomain: 'loveandlemons.com',
        servings: '4 to 6',
        prepTime: '10 minutes',
        cookTime: '10 minutes',
        totalTime: '20 minutes',
        ingredients: [
          { rawText: '2 tablespoons extra-virgin olive oil' },
          { rawText: '1 red bell pepper, stemmed, seeded, and sliced' },
          { rawText: '3 cups small broccoli florets' },
          { rawText: '½ cup water' },
          { rawText: '⅓ cup low-sodium soy sauce' },
          { rawText: '2 garlic cloves, grated' }
        ],
        steps: [
          { text: 'Make the stir fry sauce: In a medium bowl, whisk together the water, soy sauce, garlic, and ginger.' },
          { text: 'Make the stir fry. Heat the olive oil in a large skillet or wok over high heat.' },
          { text: 'Reduce the heat to medium and pour in the stir fry sauce.' }
        ]
      }
    });

    expect(scraper).toHaveBeenCalledWith({ html: '<html><title>Easy Veggie Stir Fry</title></html>' });
    expect(fetchMock).toHaveBeenNthCalledWith(
      2,
      'https://r.jina.ai/http://www.loveandlemons.com/stir-fry-recipe/',
      expect.objectContaining({ redirect: 'follow' })
    );
    expect(query).toHaveBeenNthCalledWith(3, 'COMMIT');
    expect(release).toHaveBeenCalledTimes(1);
  });

  test('prefers ICN serving measure ingredients over duplicated school-recipe schema rows', async () => {
    useTestDatabaseUrl();

    const html = `
      <div class="wprm-recipe-ingredients-container" data-servings="50">
        <h4 class="wprm-recipe-ingredient-group-name">50 Servings</h4><ul class="wprm-recipe-ingredients"></ul>
        <h4 class="wprm-recipe-ingredient-group-name">Weight</h4>
        <ul class="wprm-recipe-ingredients">
          <li class="wprm-recipe-ingredient"><span class="wprm-recipe-ingredient-amount">12</span> <span class="wprm-recipe-ingredient-unit">lbs</span> <span class="wprm-recipe-ingredient-name">Potatoes, frozen</span></li>
          <li class="wprm-recipe-ingredient"><span class="wprm-recipe-ingredient-amount">-</span> <span class="wprm-recipe-ingredient-unit">-</span> <span class="wprm-recipe-ingredient-name">Salt-free seasoning</span></li>
        </ul>
        <h4 class="wprm-recipe-ingredient-group-name">Measure</h4>
        <ul class="wprm-recipe-ingredients">
          <li class="wprm-recipe-ingredient"><span class="wprm-recipe-ingredient-amount">1 gal 3</span> <span class="wprm-recipe-ingredient-unit">qts 2 cups</span> <span class="wprm-recipe-ingredient-name">Potatoes, frozen</span></li>
          <li class="wprm-recipe-ingredient"><span class="wprm-recipe-ingredient-amount">½</span> <span class="wprm-recipe-ingredient-unit">cup</span> <span class="wprm-recipe-ingredient-name">Salt-free seasoning</span></li>
        </ul>
        <h4 class="wprm-recipe-ingredient-group-name">100 Servings</h4><ul class="wprm-recipe-ingredients"></ul>
        <h4 class="wprm-recipe-ingredient-group-name">Measure</h4>
        <ul class="wprm-recipe-ingredients">
          <li class="wprm-recipe-ingredient"><span class="wprm-recipe-ingredient-amount">3 gal 3</span> <span class="wprm-recipe-ingredient-unit">qts</span> <span class="wprm-recipe-ingredient-name">Potatoes, frozen</span></li>
        </ul>
      </div>
      <div class="wprm-recipe-instructions-container"></div>
    `;
    const scraper = vi.fn(async () => ({
      name: 'Breakfast Bowl USDA Recipe for Schools',
      recipeYield: '50',
      recipeIngredients: [
        '12 lbs Potatoes, frozen',
        '- - Salt-free seasoning',
        '1 gal 3 qts 2 cups Potatoes, frozen',
        '½ cup Salt-free seasoning',
        '3 gal 3 qts Potatoes, frozen'
      ],
      recipeInstructions: ['Serve one bowl.']
    }));
    const fetchMock = vi.fn(async () => {
      return new Response(html, { status: 200, headers: { 'content-type': 'text/html' } });
    });

    vi.stubGlobal('fetch', fetchMock);
    vi.doMock('@dimfu/recipe-scraper', () => ({ default: scraper }));

    const { importRecipeDraftForSmokeTest } = await import('../src/services/recipeImportService.js');

    await expect(
      importRecipeDraftForSmokeTest('https://theicn.org/cnrb/recipes-for-schools/breakfast-bowl-usda-recipe-for-schools/')
    ).resolves.toMatchObject({
      title: 'Breakfast Bowl USDA Recipe for Schools',
      sourceDomain: 'theicn.org',
      servings: '50',
      ingredients: [
        { rawText: '1 gal 3 qts 2 cups Potatoes, frozen' },
        { rawText: '½ cup Salt-free seasoning' }
      ],
      steps: [{ text: 'Serve one bowl.' }]
    });
  });

  test('parses Good Food reader markdown with method step markers', async () => {
    useTestDatabaseUrl();

    const markdown = `
      Title: Best ever chocolate brownies recipe | Good Food

      Markdown Content:
      # Best ever chocolate brownies recipe

      **Cuts into 16 squares or 32 triangles**

      Prep:**25 mins**

      Cook:**27 mins - 35 mins**

      ## Ingredients

      ## Nutrition

      *   185g [unsalted butter](https://example.com/butter)
      *   185g best dark chocolate
      *   85g plain flour
      *   kcal 150
      *   fat 9 g

      ## Method

      *   ### step 1

      Cut the butter into small cubes and tip into a bowl.

      *   ### step 2

      Break the chocolate into pieces and add to the bowl.
    `;
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.startsWith('https://r.jina.ai/http://')) {
        return new Response(markdown, { status: 200, headers: { 'content-type': 'text/plain' } });
      }
      return new Response('payment required', { status: 402, headers: { 'content-type': 'text/html' } });
    });

    vi.stubGlobal('fetch', fetchMock);

    const { importRecipeDraftForSmokeTest } = await import('../src/services/recipeImportService.js');

    await expect(importRecipeDraftForSmokeTest('https://www.bbcgoodfood.com/recipes/best-ever-chocolate-brownies-recipe')).resolves.toMatchObject({
      title: 'Best ever chocolate brownies',
      sourceDomain: 'bbcgoodfood.com',
      servings: '16 squares or 32 triangles',
      prepTime: '25 mins',
      cookTime: '27 mins - 35 mins',
      ingredients: [
        { rawText: '185g unsalted butter' },
        { rawText: '185g best dark chocolate' },
        { rawText: '85g plain flour' }
      ],
      steps: [
        { text: 'Cut the butter into small cubes and tip into a bowl.' },
        { text: 'Break the chocolate into pieces and add to the bowl.' }
      ]
    });
  });

  test('parses recipe card markdown with checkbox ingredients', async () => {
    useTestDatabaseUrl();

    const markdown = `
      Title: Best Lentil Soup Recipe - Cookie and Kate

      Markdown Content:
      # Best Lentil Soup Recipe - Cookie and Kate

      ## Best Lentil Soup

      *   Author: Kathryne Taylor
      *   Prep Time:10 mins
      *   Cook Time:45 mins
      *   Total Time:55 minutes
      *   Yield:4 servings

      ### Ingredients

      *   - [x] ¼ cup extra virgin olive oil
      *   - [x] 1 medium yellow or white onion, chopped
      *   - [x] 2 carrots, peeled and chopped

      ### Instructions

      1.   Warm the olive oil in a large Dutch oven over medium heat.
      2.   Add the chopped onion and carrot and cook until softened.
    `;
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.startsWith('https://r.jina.ai/http://')) {
        return new Response(markdown, { status: 200, headers: { 'content-type': 'text/plain' } });
      }
      return new Response('blocked', { status: 403, headers: { 'content-type': 'text/html' } });
    });

    vi.stubGlobal('fetch', fetchMock);

    const { importRecipeDraftForSmokeTest } = await import('../src/services/recipeImportService.js');

    await expect(importRecipeDraftForSmokeTest('https://cookieandkate.com/best-lentil-soup-recipe/')).resolves.toMatchObject({
      title: 'Best Lentil Soup',
      sourceDomain: 'cookieandkate.com',
      servings: '4 servings',
      prepTime: '10 mins',
      cookTime: '45 mins',
      totalTime: '55 minutes',
      ingredients: [
        { rawText: '¼ cup extra virgin olive oil' },
        { rawText: '1 medium yellow or white onion, chopped' },
        { rawText: '2 carrots, peeled and chopped' }
      ],
      steps: [
        { text: 'Warm the olive oil in a large Dutch oven over medium heat.' },
        { text: 'Add the chopped onion and carrot and cook until softened.' }
      ]
    });
  });
});
