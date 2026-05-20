export function buildLabelParsePrompt(args: { ocrText: string; contextNote?: string }): string {
  return `
You are parsing a Nutrition Facts panel OCR'd from a food photo.

OCR text:
"""
${args.ocrText}
"""

${args.contextNote ? `User note: "${args.contextNote}"` : ''}

Return strict JSON only:
{
  "imageType": "nutrition_label",
  "items": [{
    "name": string,
    "brand": string | null,
    "servingSize": string,
    "servingSizeG": number,
    "calories": number,
    "proteinG": number,
    "carbsG": number,
    "fatG": number,
    "fiberG": number | null,
    "sugarG": number | null,
    "sodiumMg": number | null
  }],
  "confidence": number,
  "coverage": { "score": number, "warnings": string[] }
}

Rules:
1. Use per-serving values. Prefer the literal serving size text if visible.
2. If calories are unclear, estimate with fat_g*9 + carbs_g*4 + protein_g*4.
3. Reject impossible values: calories > 1500, total fat > 100g, sodium > 3000mg.
4. If the product name is not visible, use "Packaged food (label)".
`.trim();
}
