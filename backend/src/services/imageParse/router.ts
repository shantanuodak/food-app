import * as laneBarcode from './laneBarcode.js';
import * as laneLabel from './laneLabel.js';
import * as laneVision from './laneVision.js';
import type { Cuisine } from './cuisineClassifier.js';
import type { ImagePart, ImageParseServiceResult, ImageParseLane } from './types.js';

export interface RouteImageParseArgs {
  lane: ImageParseLane;
  barcode?: { code: string; symbology?: string };
  ocrText?: string;
  image?: ImagePart;
  contextNote?: string;
  userLocale?: string;
  recentCuisines?: Cuisine[];
  clientAttemptId?: string;
  signal?: AbortSignal;
}

export async function routeImageParse(args: RouteImageParseArgs): Promise<ImageParseServiceResult & { fallback?: 'image'; laneSource?: string; laneLatencyMs?: number }> {
  switch (args.lane) {
    case 'barcode': {
      if (!args.barcode) throw new Error('barcode lane requires barcode args');
      const result = await laneBarcode.lookupBarcode({
        code: args.barcode.code,
        symbology: args.barcode.symbology,
        contextNote: args.contextNote,
        signal: args.signal
      });
      return { ...result, laneSource: result.lookup.source, laneLatencyMs: result.lookup.latencyMs };
    }
    case 'label':
      if (!args.ocrText) throw new Error('label lane requires ocrText');
      return laneLabel.parseLabel({
        ocrText: args.ocrText,
        imageBase64: args.image?.dataBase64,
        mimeType: args.image?.mimeType,
        contextNote: args.contextNote,
        signal: args.signal
      });
    case 'vision':
      if (!args.image) throw new Error('vision lane requires image');
      return laneVision.parseImage({
        image: args.image,
        contextNote: args.contextNote,
        userLocale: args.userLocale,
        recentCuisines: args.recentCuisines,
        signal: args.signal
      });
  }
}
