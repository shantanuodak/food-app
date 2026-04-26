import type { ParseResult } from './deterministicParser.js';
import { buildClarificationQuestions } from './clarificationService.js';
import { hasUnresolvedSignal } from './parsePipelineResultUtils.js';
import { config } from '../config.js';

export function computeClarificationState(text: string, result: ParseResult): { needsClarification: boolean; clarificationQuestions: string[] } {
  const itemNeedsClarification = result.items.filter((item) => item.needsClarification === true);
  const unresolved = hasUnresolvedSignal(text, result);
  const needsClarification =
    itemNeedsClarification.length > 0 ||
    result.items.length === 0 ||
    result.confidence < config.aiFallbackConfidenceMin ||
    (unresolved && result.confidence < config.aiFallbackConfidenceMax);

  if (!needsClarification) {
    return { needsClarification: false, clarificationQuestions: [] };
  }

  const questions = buildClarificationQuestions(text, result);
  if (questions.length > 0) {
    if (itemNeedsClarification.length > 0) {
      const itemLabel = itemNeedsClarification
        .map((item) => item.name.trim())
        .filter(Boolean)
        .slice(0, 3)
        .join(', ');
      questions.unshift(
        itemLabel
          ? `Please confirm quantity or serving details for: ${itemLabel}.`
          : 'Please confirm quantity or serving details for unresolved items.'
      );
    }
    return { needsClarification: true, clarificationQuestions: Array.from(new Set(questions)) };
  }

  return {
    needsClarification: true,
    clarificationQuestions: ['Please list each food with quantity, for example: "2 eggs, 1 slice toast".']
  };
}
