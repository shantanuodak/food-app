import type { ParseResult } from './deterministicParser.js';
import type { AICallUsage } from './aiNormalizerService.js';
import type { DietaryFlag } from './dietaryConflictService.js';

export type ParsePipelineRoute = 'cache' | 'deterministic' | 'gemini' | 'unresolved';

export type ParseDecisionContext = {
  userId: string;
  featureFlags: {
    geminiEnabled: boolean;
  };
  budget?: {
    dailyBudgetUsd: number;
    userSoftCapUsd: number;
    globalUsedTodayUsd: number;
    userUsedTodayUsd: number;
    userSoftCapExceeded: boolean;
  };
  cacheScope: string;
  allowFallback: boolean;
};

export type ParseDecisionResult = {
  result: ParseResult;
  route: ParsePipelineRoute;
  cacheHit: boolean;
  sourcesUsed: Array<'cache' | 'deterministic' | 'gemini' | 'manual'>;
  reasonCodes: string[];
  fallbackUsed: boolean;
  fallbackModel: string | null;
  fallbackUsage: AICallUsage | null;
  needsClarification: boolean;
  clarificationQuestions: string[];
  /**
   * Diet preference / allergy violations detected against the user's
   * onboarding profile after parsing completes. Empty array (or omitted
   * for backward compat) means no flags. Computed deterministically —
   * no extra LLM call.
   */
  dietaryFlags?: DietaryFlag[];
};

export type ParseProviderName = 'cache' | 'gemini';

export type ParseProviderInput = {
  text: string;
  baseline: ParseResult;
  context: ParseDecisionContext;
};

export type ParseProviderOutput = {
  result: ParseResult;
  accepted: boolean;
  rejectionReason?: string;
  cacheHit?: boolean;
  fallbackUsed?: boolean;
  fallbackModel?: string | null;
  fallbackUsage?: AICallUsage | null;
};

export interface ParseProvider {
  name: ParseProviderName;
  isEnabled(context: ParseDecisionContext): boolean;
  parse(input: ParseProviderInput): Promise<ParseProviderOutput | null>;
}
