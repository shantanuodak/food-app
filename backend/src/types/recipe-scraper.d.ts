declare module '@dimfu/recipe-scraper' {
  export type RecipeScraperOptions = {
    maxRedirects?: number;
    lang?: string;
    timeout?: number;
    html?: string;
    url?: string;
  };

  export type RecipeScraperResult = Partial<{
    url: string;
    name: string;
    image: string;
    description: string;
    cookTime: string;
    prepTime: string;
    totalTime: string;
    recipeYield: string;
    recipeIngredients: unknown[];
    recipeInstructions: unknown[];
    recipeCategories: unknown[];
    recipeCuisines: unknown[];
    keywords: unknown[];
  }>;

  export default function getRecipeData(
    input: string | Partial<RecipeScraperOptions>,
    inputOptions?: Partial<RecipeScraperOptions>
  ): Promise<RecipeScraperResult | undefined>;
}
