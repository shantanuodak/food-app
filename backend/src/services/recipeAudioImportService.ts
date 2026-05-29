import type { PoolClient } from 'pg';
import { config } from '../config.js';
import { pool } from '../db.js';
import { ApiError } from '../utils/errors.js';
import { ensureUserExists } from './userService.js';
import { assertSafeRecipeUrl } from './recipeImportService.js';
import type { RecipeDraft, RecipeIngredientDraft, RecipeStepDraft } from './recipeImportService.js';

const GROQ_TRANSCRIPTION_ENDPOINT = '/audio/transcriptions';
const DEFAULT_TRANSCRIPTION_PROMPT =
  'Transcribe this recipe video accurately. Preserve ingredient quantities, units, cooking temperatures, and step wording.';

type AuthContext = {
  authProvider?: string | null;
  userEmail?: string | null;
};

export type RecipeAudioFileInput = {
  buffer: Buffer;
  mimeType: string;
  filename: string;
};

export type RecipeAudioImportInput = {
  userId: string;
  auth?: AuthContext;
  sourceUrl: string;
  sourceName?: string | null;
  heroImageUrl?: string | null;
  language?: string | null;
  audio?: RecipeAudioFileInput;
  audioUrl?: string | null;
  provider?: AudioTranscriptionProvider;
};

export type RecipeAudioTranscriptionInput = {
  audio?: RecipeAudioFileInput;
  audioUrl?: string;
  language?: string | null;
  prompt?: string | null;
};

export type RecipeAudioTranscriptionResult = {
  text: string;
  provider: string;
  model: string;
  requestId?: string | null;
};

export type AudioTranscriptionProvider = {
  transcribe(input: RecipeAudioTranscriptionInput): Promise<RecipeAudioTranscriptionResult>;
};

type GroqProviderOptions = {
  apiKey?: string;
  baseUrl?: string;
  model?: string;
  timeoutMs?: number;
  fetchImpl?: typeof fetch;
};

export class GroqAudioTranscriptionProvider implements AudioTranscriptionProvider {
  private readonly apiKey: string;
  private readonly baseUrl: string;
  private readonly model: string;
  private readonly timeoutMs: number;
  private readonly fetchImpl: typeof fetch;

  constructor(options: GroqProviderOptions = {}) {
    this.apiKey = options.apiKey ?? config.groqApiKey;
    this.baseUrl = (options.baseUrl ?? config.groqApiBaseUrl).replace(/\/$/, '');
    this.model = options.model ?? config.groqAudioTranscriptionModel;
    this.timeoutMs = options.timeoutMs ?? config.recipeAudioTranscriptionTimeoutMs;
    this.fetchImpl = options.fetchImpl ?? fetch;
  }

  async transcribe(input: RecipeAudioTranscriptionInput): Promise<RecipeAudioTranscriptionResult> {
    if (!this.apiKey) {
      throw new ApiError(503, 'RECIPE_AUDIO_TRANSCRIPTION_DISABLED', 'Audio import is not configured yet');
    }

    if (!input.audio && !input.audioUrl) {
      throw new ApiError(400, 'RECIPE_AUDIO_MISSING_MEDIA', 'Provide an audio file or audio URL');
    }

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);

    try {
      const form = new FormData();
      form.set('model', this.model);
      form.set('response_format', 'json');
      form.set('temperature', '0');
      form.set('prompt', input.prompt?.trim() || DEFAULT_TRANSCRIPTION_PROMPT);
      if (input.language?.trim()) {
        form.set('language', input.language.trim().slice(0, 12));
      }

      if (input.audio) {
        form.set(
          'file',
          new Blob([new Uint8Array(input.audio.buffer)], { type: input.audio.mimeType || 'application/octet-stream' }),
          safeFilename(input.audio.filename)
        );
      } else if (input.audioUrl) {
        form.set('url', input.audioUrl);
      }

      const response = await this.fetchImpl(`${this.baseUrl}${GROQ_TRANSCRIPTION_ENDPOINT}`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${this.apiKey}`
        },
        body: form,
        signal: controller.signal
      });

      const responseText = await response.text();
      if (!response.ok) {
        throw new ApiError(
          response.status >= 500 ? 502 : response.status,
          'RECIPE_AUDIO_TRANSCRIPTION_FAILED',
          groqErrorMessage(response.status, responseText)
        );
      }

      const parsed = parseGroqTranscriptionResponse(responseText);
      return {
        text: parsed.text,
        provider: 'groq',
        model: this.model,
        requestId: parsed.requestId
      };
    } catch (error) {
      if (error instanceof ApiError) {
        throw error;
      }
      if (error instanceof Error && error.name === 'AbortError') {
        throw new ApiError(504, 'RECIPE_AUDIO_TRANSCRIPTION_TIMEOUT', 'Audio transcription timed out');
      }
      throw new ApiError(502, 'RECIPE_AUDIO_TRANSCRIPTION_FAILED', 'Audio transcription failed');
    } finally {
      clearTimeout(timeout);
    }
  }
}

export function buildRecipeDraftFromTranscript(input: {
  transcript: string;
  sourceUrl: string;
  sourceName?: string | null;
  heroImageUrl?: string | null;
  provider?: string;
  model?: string;
}): RecipeDraft {
  const source = assertSafeRecipeUrl(input.sourceUrl);
  const transcript = cleanText(input.transcript, 20_000);
  if (!transcript) {
    throw new ApiError(422, 'RECIPE_AUDIO_EMPTY_TRANSCRIPT', 'Audio transcription did not produce usable text');
  }

  const lines = transcriptLines(transcript);
  const ingredients = extractIngredients(transcript, lines).map(toIngredientDraft);
  if (ingredients.length === 0) {
    throw new ApiError(
      422,
      'RECIPE_AUDIO_NO_RECIPE_TEXT',
      'Audio transcript did not include enough ingredient details'
    );
  }

  const steps = extractSteps(lines, transcript).map((text) => ({ text }));
  const title = inferTitle(lines, input.sourceName) ?? 'Imported audio recipe';
  const warnings = [
    'Imported from audio transcription. Review before saving.',
    ...(steps.length === 0 ? ['No clear instructions were found in the transcript.'] : [])
  ];

  return {
    title,
    sourceUrl: source.url,
    sourceDomain: source.domain,
    sourceName: cleanText(input.sourceName, 180) ?? source.domain,
    heroImageUrl: cleanHttpUrl(input.heroImageUrl),
    description: null,
    servings: null,
    prepTime: null,
    cookTime: null,
    totalTime: null,
    categories: [],
    cuisines: [],
    keywords: ['audio import'],
    ingredients,
    steps,
    confidence: steps.length > 0 ? 0.58 : 0.48,
    warnings
  };
}

export async function importRecipeFromAudio(input: RecipeAudioImportInput): Promise<{
  importId: string;
  draft: RecipeDraft;
  transcript: string;
  transcription: {
    provider: string;
    model: string;
    requestId?: string | null;
  };
}> {
  if (!config.recipeAudioImportEnabled) {
    throw new ApiError(503, 'RECIPE_AUDIO_IMPORT_DISABLED', 'Audio recipe import is not enabled');
  }

  const source = assertSafeRecipeUrl(input.sourceUrl);
  const audioUrl = cleanText(input.audioUrl, 3000);
  if (audioUrl) {
    assertSafeRecipeUrl(audioUrl);
  }

  if (!input.audio && !audioUrl) {
    throw new ApiError(400, 'RECIPE_AUDIO_MISSING_MEDIA', 'Provide an audio file or audio URL');
  }

  if (input.audio) {
    validateAudioFile(input.audio);
  }

  const provider = input.provider ?? new GroqAudioTranscriptionProvider();
  const transcription = await provider.transcribe({
    audio: input.audio,
    audioUrl: audioUrl ?? undefined,
    language: input.language,
    prompt: DEFAULT_TRANSCRIPTION_PROMPT
  });

  const draft = buildRecipeDraftFromTranscript({
    transcript: transcription.text,
    sourceUrl: source.url,
    sourceName: input.sourceName,
    heroImageUrl: input.heroImageUrl,
    provider: transcription.provider,
    model: transcription.model
  });

  const importId = await insertRecipeImportDraft({
    userId: input.userId,
    auth: input.auth,
    draft,
    transcript: transcription.text,
    transcription
  });

  draft.warnings = [...draft.warnings, `Transcript provider: ${transcription.provider}/${transcription.model}.`];
  return {
    importId,
    draft,
    transcript: transcription.text,
    transcription: {
      provider: transcription.provider,
      model: transcription.model,
      requestId: transcription.requestId
    }
  };
}

async function insertRecipeImportDraft(input: {
  userId: string;
  auth?: AuthContext;
  draft: RecipeDraft;
  transcript: string;
  transcription: RecipeAudioTranscriptionResult;
}): Promise<string> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await ensureUserExists(input.userId, { authProvider: input.auth?.authProvider, email: input.auth?.userEmail }, client);
    const inserted = await client.query<{ id: string }>(
      `
      INSERT INTO recipe_imports (user_id, source_url, source_domain, status, draft_json)
      VALUES ($1, $2, $3, 'draft', $4::jsonb)
      RETURNING id
      `,
      [
        input.userId,
        input.draft.sourceUrl,
        input.draft.sourceDomain,
        JSON.stringify({
          ...input.draft,
          importSource: 'audio-transcription',
          transcript: input.transcript,
          transcription: {
            provider: input.transcription.provider,
            model: input.transcription.model,
            requestId: input.transcription.requestId ?? null
          }
        })
      ]
    );
    await client.query('COMMIT');
    return inserted.rows[0]!.id;
  } catch (error) {
    await rollbackQuietly(client);
    throw error;
  } finally {
    client.release();
  }
}

async function rollbackQuietly(client: PoolClient): Promise<void> {
  try {
    await client.query('ROLLBACK');
  } catch {
    // Preserve the original failure.
  }
}

function validateAudioFile(audio: RecipeAudioFileInput): void {
  if (audio.buffer.length === 0) {
    throw new ApiError(400, 'RECIPE_AUDIO_EMPTY_FILE', 'Audio file is empty');
  }
  if (audio.buffer.length > config.recipeAudioMaxBytes) {
    throw new ApiError(413, 'RECIPE_AUDIO_FILE_TOO_LARGE', 'Audio file is too large');
  }
  const extension = extensionFor(audio.filename);
  const supported = new Set(['flac', 'mp3', 'mp4', 'mpeg', 'mpga', 'm4a', 'ogg', 'wav', 'webm']);
  if (extension && !supported.has(extension)) {
    throw new ApiError(400, 'RECIPE_AUDIO_UNSUPPORTED_TYPE', 'Audio file type is not supported');
  }
}

function parseGroqTranscriptionResponse(responseText: string): { text: string; requestId?: string | null } {
  try {
    const parsed = JSON.parse(responseText) as { text?: unknown; x_groq?: { id?: unknown } };
    const text = cleanText(parsed.text, 100_000);
    if (!text) {
      throw new Error('missing text');
    }
    return {
      text,
      requestId: cleanText(parsed.x_groq?.id, 120)
    };
  } catch {
    const text = cleanText(responseText, 100_000);
    if (!text) {
      throw new ApiError(502, 'RECIPE_AUDIO_TRANSCRIPTION_EMPTY', 'Audio transcription returned no text');
    }
    return { text, requestId: null };
  }
}

function groqErrorMessage(status: number, body: string): string {
  const fallback = `Audio transcription failed (${status})`;
  try {
    const parsed = JSON.parse(body) as { error?: { message?: unknown } };
    return cleanText(parsed.error?.message, 500) ?? fallback;
  } catch {
    return cleanText(body, 500) ?? fallback;
  }
}

function cleanText(value: unknown, maxLength = 1000): string | null {
  if (typeof value !== 'string' && typeof value !== 'number') {
    return null;
  }
  const cleaned = String(value)
    .replace(/\u00a0/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return cleaned ? cleaned.slice(0, maxLength) : null;
}

function cleanHttpUrl(value: unknown): string | null {
  const cleaned = cleanText(value, 1000);
  if (!cleaned) {
    return null;
  }
  try {
    const url = new URL(cleaned);
    if (url.protocol !== 'http:' && url.protocol !== 'https:') {
      return null;
    }
    return url.toString();
  } catch {
    return null;
  }
}

function safeFilename(filename: string): string {
  const cleaned = cleanText(filename, 180)?.replace(/[^a-z0-9._-]/gi, '_') ?? 'recipe-audio.m4a';
  return cleaned.includes('.') ? cleaned : `${cleaned}.m4a`;
}

function extensionFor(filename: string): string | null {
  const extension = filename.toLowerCase().split('.').pop();
  return extension && extension !== filename.toLowerCase() ? extension : null;
}

function transcriptLines(transcript: string): string[] {
  return transcript
    .replace(/[•·]/g, '\n')
    .split(/\n+|(?<=[.!?])\s+/)
    .map((line) => cleanText(line, 2000))
    .filter((line): line is string => Boolean(line));
}

function toIngredientDraft(rawText: string): RecipeIngredientDraft {
  return {
    rawText,
    quantityText: null,
    unitText: null,
    ingredientName: null
  };
}

function inferTitle(lines: string[], sourceName?: string | null): string | null {
  const sourceTitle = cleanText(sourceName, 90);
  if (sourceTitle && !isSocialSourceName(sourceTitle)) {
    return sourceTitle;
  }

  for (const line of lines.slice(0, 5)) {
    const recipeTitle = line.match(/\b([a-z][a-z\s'-]{3,80}\s+recipe)\b/i)?.[1];
    if (recipeTitle) {
      return titleCase(recipeTitle);
    }
    if (!looksLikeIngredient(line) && !isInstructionLike(line) && line.length <= 90) {
      return titleCase(line.replace(/^(today|now|first|next),?\s+/i, ''));
    }
  }
  return null;
}

function isSocialSourceName(sourceName: string): boolean {
  return /^(facebook|instagram|tiktok|youtube|pinterest|web page)$/i.test(sourceName.trim());
}

function titleCase(value: string): string {
  return value
    .trim()
    .replace(/\s+/g, ' ')
    .replace(/\b([a-z])/g, (match) => match.toUpperCase())
    .slice(0, 180);
}

function extractIngredients(transcript: string, lines: string[]): string[] {
  const sectionIngredients = extractIngredientsFromSection(lines);
  const quantityIngredients = extractQuantityIngredients(transcript);
  const toTasteIngredients = Array.from(transcript.matchAll(/\b([a-z][a-z\s-]{1,40}?)\s+to taste\b/gi)).map((match) =>
    cleanIngredient(`${match[1]} to taste`)
  );

  return uniqueStrings([...sectionIngredients, ...quantityIngredients, ...toTasteIngredients].filter(Boolean) as string[]).slice(
    0,
    80
  );
}

function extractIngredientsFromSection(lines: string[]): string[] {
  const startIndex = lines.findIndex((line) => /\bingredients?\b/i.test(line));
  if (startIndex < 0) {
    return [];
  }

  const endIndex = lines.findIndex((line, index) => index > startIndex && /\b(instructions?|directions?|method|steps?)\b/i.test(line));
  const firstLineTail = textAfterSectionHeading(lines[startIndex]!, /\bingredients?\b/i);
  const section = [firstLineTail, ...lines.slice(startIndex + 1, endIndex > startIndex ? endIndex : lines.length)]
    .filter((line): line is string => Boolean(line))
    .join(', ');
  return splitIngredientText(section).filter(looksLikeIngredient);
}

function extractQuantityIngredients(transcript: string): string[] {
  const normalized = normalizeNumberWords(transcript)
    .replace(/\b(one half|a half)\b/gi, '1/2')
    .replace(/\bquarter\b/gi, '1/4');

  const quantityPattern =
    /\b(?:\d+(?:\s*\/\s*\d+)?|[¼½¾⅓⅔⅛⅜⅝⅞]|a|an)\s+(?:and\s+)?(?:\d+\s*\/\s*\d+\s+)?[a-z][a-z0-9%.'’/-]*(?:\s+[a-z][a-z0-9%.'’/-]*){0,10}/gi;
  const matches = Array.from(normalized.matchAll(quantityPattern)).map((match) => match[0]);
  return splitIngredientText(matches.join(', ')).filter(looksLikeIngredient);
}

function splitIngredientText(value: string): string[] {
  return value
    .split(/[,;]|\band then\b|\bthen\b/gi)
    .map(cleanIngredient)
    .filter((line): line is string => Boolean(line));
}

function cleanIngredient(value: string | undefined): string | null {
  const cleaned = cleanText(
    (value ?? '')
      .replace(/^(and|plus|with)\s+/i, '')
      .replace(/\b(add|mix|cook|bake|fry|saute|sauté|place|put|season|stir)\b.*$/i, '')
      .replace(/\s+/g, ' '),
    700
  );
  if (!cleaned || cleaned.length < 3 || cleaned.length > 140) {
    return null;
  }
  return cleaned;
}

function looksLikeIngredient(value: string): boolean {
  const lower = value.toLowerCase();
  if (/\b(instruction|direction|method|step|recipe|video|subscribe|follow|like|comment|share)\b/.test(lower)) {
    return false;
  }
  if (/^(?:\d+(?:\s*\/\s*\d+)?|[¼½¾⅓⅔⅛⅜⅝⅞]|a|an)\s+\S+/.test(lower)) {
    return true;
  }
  return /\b(cup|cups|tbsp|tablespoons?|tsp|teaspoons?|grams?|kg|g|ml|liters?|litres?|oz|ounces?|lbs?|pounds?|pinch|cloves?|cans?|packets?|sticks?|slices?|to taste)\b/.test(
    lower
  );
}

function extractSteps(lines: string[], transcript: string): string[] {
  const sectionSteps = extractStepsFromSection(lines);
  if (sectionSteps.length > 0) {
    return sectionSteps;
  }

  return uniqueStrings(
    transcriptLines(transcript)
      .map((line) => cleanText(line, 2000))
      .filter((line): line is string => Boolean(line && isInstructionLike(line)))
  ).slice(0, 80);
}

function extractStepsFromSection(lines: string[]): string[] {
  const startIndex = lines.findIndex((line) => /\b(instructions?|directions?|method|steps?)\b/i.test(line));
  if (startIndex < 0) {
    return [];
  }

  const firstLineTail = textAfterSectionHeading(lines[startIndex]!, /\b(instructions?|directions?|method|steps?)\b/i);
  return [firstLineTail, ...lines.slice(startIndex + 1)]
    .filter((line): line is string => Boolean(line))
    .map((line) => line.replace(/^\s*(?:\d+[\.)]|[-*])\s*/, ''))
    .map((line) => cleanText(line, 2000))
    .filter((line): line is string => Boolean(line && line.length >= 8 && !looksLikeIngredient(line)));
}

function textAfterSectionHeading(line: string, headingPattern: RegExp): string | null {
  const match = headingPattern.exec(line);
  if (!match || match.index < 0) {
    return null;
  }
  const tail = line.slice(match.index + match[0].length).replace(/^[:\s-]+/, '');
  return cleanText(tail, 2000);
}

function isInstructionLike(value: string): boolean {
  return /^(add|arrange|bake|blend|boil|bring|chill|chop|combine|cook|cover|dice|drain|fry|grill|heat|mix|place|pour|preheat|reduce|remove|roast|saute|sauté|season|serve|simmer|slice|stir|top|transfer|whisk)\b/i.test(
    value
  );
}

function normalizeNumberWords(value: string): string {
  const numberWords: Record<string, string> = {
    one: '1',
    two: '2',
    three: '3',
    four: '4',
    five: '5',
    six: '6',
    seven: '7',
    eight: '8',
    nine: '9',
    ten: '10',
    eleven: '11',
    twelve: '12',
    half: '1/2'
  };
  return value.replace(/\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|half)\b/gi, (match) => {
    return numberWords[match.toLowerCase()] ?? match;
  });
}

function uniqueStrings(values: string[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const value of values) {
    const key = value.toLowerCase();
    if (!seen.has(key)) {
      seen.add(key);
      result.push(value);
    }
  }
  return result;
}
