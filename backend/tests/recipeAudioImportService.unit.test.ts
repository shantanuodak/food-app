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

describe('recipeAudioImportService.buildRecipeDraftFromTranscript', () => {
  test('turns a spoken ingredient list into a reviewable recipe draft', async () => {
    useTestDatabaseUrl();
    const { buildRecipeDraftFromTranscript } = await import('../src/services/recipeAudioImportService.js');

    const draft = buildRecipeDraftFromTranscript({
      transcript:
        'Chicken breast recipe. Ingredients: four chicken breasts, one red onion, two tomatoes, two tablespoons olive oil, half cup soy sauce, salt to taste, black pepper to taste, oregano to taste. Instructions: add everything to a baking dish. Bake until the chicken is cooked through.',
      sourceUrl: 'https://www.facebook.com/reel/971768140602741/',
      sourceName: 'Facebook'
    });

    expect(draft).toMatchObject({
      sourceDomain: 'facebook.com',
      sourceName: 'Facebook',
      confidence: 0.58
    });
    expect(draft.title).toContain('Chicken Breast Recipe');
    expect(draft.ingredients.map((ingredient) => ingredient.rawText)).toEqual(
      expect.arrayContaining([
        '4 chicken breasts',
        '1 red onion',
        '2 tomatoes',
        '2 tablespoons olive oil',
        '1/2 cup soy sauce',
        'salt to taste',
        'black pepper to taste',
        'oregano to taste'
      ])
    );
    expect(draft.steps.map((step) => step.text)).toEqual([
      'add everything to a baking dish.',
      'Bake until the chicken is cooked through.'
    ]);
    expect(draft.warnings).toContain('Imported from audio transcription. Review before saving.');
  });

  test('rejects transcripts without ingredients', async () => {
    useTestDatabaseUrl();
    const { buildRecipeDraftFromTranscript } = await import('../src/services/recipeAudioImportService.js');

    expect(() =>
      buildRecipeDraftFromTranscript({
        transcript: 'This video is about dinner and everyone loved it.',
        sourceUrl: 'https://www.example.com/video'
      })
    ).toThrow(expect.objectContaining({ code: 'RECIPE_AUDIO_NO_RECIPE_TEXT' }));
  });
});

describe('recipeAudioImportService.GroqAudioTranscriptionProvider', () => {
  test('calls Groq transcription endpoint with audio URL through a provider abstraction', async () => {
    useTestDatabaseUrl();
    const fetchMock = vi.fn(async (_url: string | URL | Request, init?: RequestInit) => {
      const form = init?.body as FormData;
      expect(form.get('model')).toBe('whisper-large-v3-turbo');
      expect(form.get('url')).toBe('https://cdn.example.com/video.m4a');
      expect(form.get('response_format')).toBe('json');
      expect(init?.headers).toEqual({ Authorization: 'Bearer test-groq-key' });
      return new Response(JSON.stringify({ text: 'one cup rice', x_groq: { id: 'req_123' } }), {
        status: 200,
        headers: { 'content-type': 'application/json' }
      });
    });

    const { GroqAudioTranscriptionProvider } = await import('../src/services/recipeAudioImportService.js');
    const provider = new GroqAudioTranscriptionProvider({
      apiKey: 'test-groq-key',
      baseUrl: 'https://api.groq.test/openai/v1',
      model: 'whisper-large-v3-turbo',
      fetchImpl: fetchMock as typeof fetch
    });

    await expect(provider.transcribe({ audioUrl: 'https://cdn.example.com/video.m4a', language: 'en' })).resolves.toEqual({
      text: 'one cup rice',
      provider: 'groq',
      model: 'whisper-large-v3-turbo',
      requestId: 'req_123'
    });
    expect(fetchMock).toHaveBeenCalledWith(
      'https://api.groq.test/openai/v1/audio/transcriptions',
      expect.objectContaining({ method: 'POST' })
    );
  });
});

describe('recipeAudioImportService.importRecipeFromAudio', () => {
  test('transcribes through injected provider and stores the draft with transcript metadata', async () => {
    useTestDatabaseUrl();
    process.env.GROQ_API_KEY = 'unused-with-injected-provider';

    const query = vi
      .fn()
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [{ id: '88888888-8888-8888-8888-888888888888' }] })
      .mockResolvedValueOnce({ rows: [] });
    const release = vi.fn();
    const provider = {
      transcribe: vi.fn(async () => ({
        text: 'Ingredients: one cup rice, two cups water, salt to taste. Instructions: simmer until tender.',
        provider: 'groq',
        model: 'whisper-large-v3-turbo',
        requestId: 'req_audio_test'
      }))
    };

    vi.doMock('../src/db.js', () => ({
      pool: {
        connect: vi.fn(async () => ({ query, release }))
      }
    }));
    vi.doMock('../src/services/userService.js', () => ({
      ensureUserExists: vi.fn(async () => undefined)
    }));

    const { importRecipeFromAudio } = await import('../src/services/recipeAudioImportService.js');
    const result = await importRecipeFromAudio({
      userId: '11111111-1111-1111-1111-111111111111',
      auth: { authProvider: 'dev', userEmail: 'user@example.com' },
      sourceUrl: 'https://www.tiktok.com/@cook/video/123',
      sourceName: 'TikTok',
      audioUrl: 'https://cdn.example.com/video.m4a',
      provider
    });

    expect(result.importId).toBe('88888888-8888-8888-8888-888888888888');
    expect(result.transcription).toMatchObject({ provider: 'groq', model: 'whisper-large-v3-turbo' });
    expect(result.draft.ingredients.map((ingredient) => ingredient.rawText)).toEqual(
      expect.arrayContaining(['1 cup rice', '2 cups water', 'salt to taste'])
    );
    expect(provider.transcribe).toHaveBeenCalledWith(
      expect.objectContaining({
        audioUrl: 'https://cdn.example.com/video.m4a',
        prompt: expect.stringContaining('Transcribe this recipe video')
      })
    );
    expect(query).toHaveBeenNthCalledWith(1, 'BEGIN');
    expect(query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('INSERT INTO recipe_imports'),
      expect.arrayContaining(['11111111-1111-1111-1111-111111111111', 'https://www.tiktok.com/@cook/video/123'])
    );
    expect(query).toHaveBeenNthCalledWith(3, 'COMMIT');
    expect(release).toHaveBeenCalledTimes(1);
  });
});
