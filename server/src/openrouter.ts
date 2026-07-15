export type RerankCandidate = {
  catalogID: number;
  title: string;
  genres: string[];
  runtimeMinutes: number;
  rating: number;
  providers: string[];
  deterministicScore: number;
  deterministicReason: string;
};

export type RerankRequest = {
  mood: string;
  maximumRuntimeMinutes: number | null;
  candidates: RerankCandidate[];
};

type OpenRouterResponse = {
  choices?: Array<{
    message?: {
      content?: string;
    };
  }>;
};

type Fetching = (
  input: string | URL | Request,
  init?: RequestInit,
) => Promise<Response>;

type OpenRouterOptions = {
  model: string;
  siteURL?: string;
  appName?: string;
  fetcher?: Fetching;
};

const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

export async function rerankWithOpenRouter(
  apiKey: string,
  request: RerankRequest,
  options: OpenRouterOptions,
): Promise<number[]> {
  const model = options.model.trim();
  if (!model) throw new Error("OPENROUTER_MODEL is not configured");

  const allowedIDs = new Set(request.candidates.map((candidate) => candidate.catalogID));
  const fetcher = options.fetcher ?? fetch;
  const response = await fetcher(OPENROUTER_URL, {
    method: "POST",
    headers: openRouterHeaders(apiKey, options),
    body: JSON.stringify({
      model,
      messages: [
        {
          role: "system",
          content: [
            "Rerank only the supplied catalog candidates for tonight.",
            "Respect the requested mood and maximum runtime.",
            "Use deterministicScore as a strong prior, then quality, genres, and provider fit.",
            "Never add or remove IDs. Return every catalog ID exactly once.",
          ].join(" "),
        },
        {
          role: "user",
          content: JSON.stringify(request),
        },
      ],
      response_format: {
        type: "json_schema",
        json_schema: {
          name: "opentv_recommendation_ranking",
          strict: true,
          schema: {
            type: "object",
            properties: {
              catalogIDs: {
                type: "array",
                items: { type: "integer" },
              },
            },
            required: ["catalogIDs"],
            additionalProperties: false,
          },
        },
      },
      stream: false,
    }),
    signal: AbortSignal.timeout(8_000),
  });

  if (!response.ok) throw new Error(`OpenRouter returned ${response.status}`);
  const payload = await response.json() as OpenRouterResponse;
  const content = payload.choices?.[0]?.message?.content;
  if (!content) throw new Error("OpenRouter returned no structured output");

  return validateRanking(content, allowedIDs);
}

function openRouterHeaders(apiKey: string, options: OpenRouterOptions): HeadersInit {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${apiKey}`,
    "Content-Type": "application/json",
    "X-OpenRouter-Title": options.appName ?? "OpenTV",
  };
  if (options.siteURL) headers["HTTP-Referer"] = options.siteURL;
  return headers;
}

function validateRanking(content: string, allowedIDs: Set<number>): number[] {
  const parsed = JSON.parse(content) as { catalogIDs?: unknown };
  if (!Array.isArray(parsed.catalogIDs)) throw new Error("OpenRouter returned an invalid ranking");
  const ids = parsed.catalogIDs.filter((value): value is number => Number.isInteger(value));
  if (ids.length !== allowedIDs.size || new Set(ids).size !== allowedIDs.size) {
    throw new Error("OpenRouter returned duplicate or missing candidates");
  }
  if (ids.some((id) => !allowedIDs.has(id))) throw new Error("OpenRouter returned an unknown candidate");
  return ids;
}
