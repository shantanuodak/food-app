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

    const { importRecipeFromUrl } = await import('../src/services/recipeImportService.js');

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

    const { importRecipeFromUrl } = await import('../src/services/recipeImportService.js');

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

    const { importRecipeFromUrl } = await import('../src/services/recipeImportService.js');

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
});
