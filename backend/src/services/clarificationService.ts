import type { ParseResult } from './deterministicParser.js';
import { splitFoodTextSegments } from './foodTextSegmentation.js';

function hasQuantity(text: string): boolean {
  return /\b\d+(?:\.\d+)?\b/.test(text);
}

function isRestaurantLike(text: string): boolean {
  return /\b(cafe|restaurant|menu|takeout|delivery|combo|meal)\b/i.test(text);
}

function mentionsPreparation(text: string): boolean {
  return /\b(fried|grilled|baked|with|without|sauce|dressing|oil|butter)\b/i.test(text);
}

function questionFromSegment(segment: string): string {
  if (isRestaurantLike(segment)) {
    return `For "${segment}", what was the exact menu item name and portion size?`;
  }
  if (!hasQuantity(segment)) {
    return `For "${segment}", approximately how much did you have (for example, cups, slices, or grams)?`;
  }
  if (mentionsPreparation(segment)) {
    return `For "${segment}", can you confirm preparation details (for example sauce, oil, or butter)?`;
  }
  return `For "${segment}", can you provide a bit more detail so I can match the exact food?`;
}

export function buildClarificationQuestions(inputText: string, result: ParseResult): string[] {
  const questions: string[] = [];
  const segments = splitFoodTextSegments(inputText);

  for (const segment of segments) {
    const q = questionFromSegment(segment);
    if (!questions.includes(q)) {
      questions.push(q);
    }
    if (questions.length >= 2) {
      return questions;
    }
  }

  if (result.items.length === 0) {
    questions.push('Please list each food with quantity, for example: "2 eggs, 1 slice toast".');
  } else if (result.confidence < 0.5) {
    questions.push(`Could you be more specific about portions in "${inputText}"?`);
  }

  return questions.slice(0, 2);
}
