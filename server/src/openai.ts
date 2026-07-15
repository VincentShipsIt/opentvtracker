type RerankCandidate = {
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

type OpenAIResponse = {
  output_text?: string;
  output?: Array<{
    type?: string;
    content?: Array<{ type?: string; text?: string }>;
  }>;
};

export async function rerankWithOpenAI(
  apiKey: string,
  request: RerankRequest,
): Promise<number[]> {
  const allowedIDs = new Set(request.candidates.map((candidate) => candidate.catalogID));
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: Bun.env.OPENAI_RERANK_MODEL ?? "gpt-5.6-luna",
      instructions: [
        "Rerank only the supplied catalog candidates for tonight.",
        "Respect the requested mood and maximum runtime.",
        "Use deterministicScore as a strong prior, then quality, genres, and provider fit.",
        "Never add or remove IDs. Return every catalog ID exactly once.",
      ].join(" "),
      input: JSON.stringify(request),
      text: {
        format: {
          type: "json_schema",
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
    }),
    signal: AbortSignal.timeout(2_200),
  });

  if (!response.ok) throw new Error(`OpenAI returned ${response.status}`);
  const payload = await response.json() as OpenAIResponse;
  const text = payload.output_text ?? payload.output
    ?.flatMap((item) => item.content ?? [])
    .find((content) => content.type === "output_text")
    ?.text;
  if (!text) throw new Error("OpenAI returned no structured output");

  const parsed = JSON.parse(text) as { catalogIDs?: unknown };
  if (!Array.isArray(parsed.catalogIDs)) throw new Error("OpenAI returned an invalid ranking");
  const ids = parsed.catalogIDs.filter((value): value is number => Number.isInteger(value));
  if (ids.length !== allowedIDs.size || new Set(ids).size !== allowedIDs.size) {
    throw new Error("OpenAI returned duplicate or missing candidates");
  }
  if (ids.some((id) => !allowedIDs.has(id))) throw new Error("OpenAI returned an unknown candidate");
  return ids;
}
