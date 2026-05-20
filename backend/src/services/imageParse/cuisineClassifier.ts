import { config } from '../../config.js';
import { generateGeminiMultimodalText } from '../geminiFlashClient.js';
import { CUISINE_KEYWORDS } from './prompts/keywords.js';

export type Cuisine = 'indian' | 'us' | 'western' | 'eastAsian' | 'mediterranean' | 'latin' | 'generic';

export interface CuisineClassification {
  cuisine: Cuisine;
  confidence: number;
  source: 'keywords' | 'locale' | 'history' | 'classifier_call' | 'default';
  matchedKeywords?: string[];
}

const cuisines: Cuisine[] = ['indian', 'us', 'western', 'eastAsian', 'mediterranean', 'latin', 'generic'];

function normalizeText(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim();
}

function keywordMatches(contextNote: string): CuisineClassification | null {
  const normalized = normalizeText(contextNote);
  if (!normalized) return null;

  if (normalized.includes('pizza')) {
    const mediterraneanSignals = ['margherita', 'wood fired', 'neapolitan', 'mozzarella', 'focaccia', 'caprese', 'prosciutto'];
    const usSignals = ['pepperoni', 'deep dish', 'stuffed crust', 'slice', 'ranch', 'wings', 'supreme'];
    const mediterraneanCount = mediterraneanSignals.filter((signal) => normalized.includes(signal)).length;
    const usCount = usSignals.filter((signal) => normalized.includes(signal)).length;
    if (usCount > mediterraneanCount) {
      return { cuisine: 'us', confidence: usCount >= 2 ? 0.85 : 0.72, source: 'keywords', matchedKeywords: ['pizza'] };
    }
    if (mediterraneanCount > 0) {
      return { cuisine: 'mediterranean', confidence: mediterraneanCount >= 2 ? 0.85 : 0.72, source: 'keywords', matchedKeywords: ['pizza'] };
    }
  }

  const scored = cuisines
    .filter((cuisine) => cuisine !== 'generic')
    .map((cuisine) => {
      const matchedKeywords = CUISINE_KEYWORDS[cuisine].filter((keyword) => {
        const pattern = new RegExp(`(^|\\s)${keyword.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}($|\\s)`, 'i');
        return pattern.test(normalized);
      });
      return { cuisine, matchedKeywords, score: matchedKeywords.length };
    })
    .sort((a, b) => b.score - a.score);

  const [top, runnerUp] = scored;
  if (!top || top.score === 0) return null;

  if (top.cuisine === 'latin' || top.cuisine === 'us') {
    const latinSignals = ['salsa', 'mole', 'arepa', 'empanada', 'pupusa', 'queso fresco', 'plantain', 'ceviche'];
    const usSignals = ['fries', 'ranch', 'mac and cheese', 'burger', 'bbq', 'bacon'];
    const latinCount = latinSignals.filter((signal) => normalized.includes(signal)).length;
    const usCount = usSignals.filter((signal) => normalized.includes(signal)).length;
    if (latinCount > usCount) {
      return { cuisine: 'latin', confidence: 0.85, source: 'keywords', matchedKeywords: top.matchedKeywords };
    }
    if (usCount > latinCount) {
      return { cuisine: 'us', confidence: 0.85, source: 'keywords', matchedKeywords: top.matchedKeywords };
    }
  }

  const margin = top.score - (runnerUp?.score ?? 0);
  if (top.score >= 3 && margin >= 2) {
    return { cuisine: top.cuisine, confidence: 0.85, source: 'keywords', matchedKeywords: top.matchedKeywords };
  }
  if (top.score >= 1 && margin >= 1) {
    return { cuisine: top.cuisine, confidence: top.score >= 2 ? 0.72 : 0.62, source: 'keywords', matchedKeywords: top.matchedKeywords };
  }
  return null;
}

function localeOrHistory(args: { userLocale?: string; recentCuisines?: Cuisine[] }): CuisineClassification | null {
  const locale = (args.userLocale ?? '').toLowerCase();
  const recent = args.recentCuisines ?? [];
  const counts = recent.reduce<Record<string, number>>((acc, cuisine) => {
    acc[cuisine] = (acc[cuisine] ?? 0) + 1;
    return acc;
  }, {});
  const topRecent = Object.entries(counts).sort((a, b) => b[1] - a[1])[0] as [Cuisine, number] | undefined;

  if (locale.includes('-in') || locale === 'hi' || locale.startsWith('hi-')) {
    return { cuisine: 'indian', confidence: topRecent?.[0] === 'indian' ? 0.78 : 0.68, source: topRecent?.[0] === 'indian' ? 'history' : 'locale' };
  }
  if (topRecent && topRecent[1] >= 4 && topRecent[0] !== 'generic') {
    return { cuisine: topRecent[0], confidence: 0.7, source: 'history' };
  }
  if (locale.includes('-us')) {
    return { cuisine: 'us', confidence: 0.55, source: 'locale' };
  }
  return null;
}

async function classifierCall(thumbnailBase64?: string): Promise<CuisineClassification | null> {
  if (!thumbnailBase64 || !config.geminiApiKey) return null;
  const response = await generateGeminiMultimodalText({
    model: config.aiImageCaptionModel,
    temperature: 0,
    maxOutputTokens: 8,
    timeoutMs: 900,
    maxAttempts: 1,
    parts: [
      {
        text: `Classify this food photo into one token: indian, us, western, eastAsian, mediterranean, latin, generic. Return only the token.`
      },
      { inlineData: { mimeType: 'image/jpeg', data: thumbnailBase64 } }
    ]
  });
  const token = response?.jsonText.trim().replace(/[^a-zA-Z]/g, '') as Cuisine | '';
  return cuisines.includes(token as Cuisine)
    ? { cuisine: token as Cuisine, confidence: 0.72, source: 'classifier_call' }
    : null;
}

export async function classify(args: {
  contextNote?: string;
  userLocale?: string;
  recentCuisines?: Cuisine[];
  thumbnailBase64?: string;
}): Promise<CuisineClassification> {
  const keyword = keywordMatches(args.contextNote ?? '');
  if (keyword && keyword.confidence >= 0.6) return keyword;

  const freeSignal = localeOrHistory(args);
  if (freeSignal && freeSignal.confidence >= 0.6) return freeSignal;

  const modelSignal = await classifierCall(args.thumbnailBase64);
  if (modelSignal && modelSignal.confidence >= 0.6) return modelSignal;

  return { cuisine: 'generic', confidence: 0.3, source: 'default' };
}
