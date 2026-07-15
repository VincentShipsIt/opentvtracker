import { describe, expect, test } from "bun:test";
import { rerankWithOpenRouter, type RerankRequest } from "../src/openrouter";

describe("rerankWithOpenRouter", () => {
  test("sends a structured-output request and returns the validated order", async () => {
    let requestURL = "";
    let requestHeaders = new Headers();
    let requestBody: Record<string, unknown> = {};

    const ranking = await rerankWithOpenRouter("test-key", request, {
      model: "anthropic/claude-sonnet-4.5",
      siteURL: "https://opentvtracker.onrender.com",
      appName: "OpenTV",
      fetcher: async (input, init) => {
        requestURL = input.toString();
        requestHeaders = new Headers(init?.headers);
        requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
        return Response.json({
          choices: [{ message: { content: JSON.stringify({ catalogIDs: [202, 101] }) } }],
        });
      },
    });

    expect(ranking).toEqual([202, 101]);
    expect(requestURL).toBe("https://openrouter.ai/api/v1/chat/completions");
    expect(requestHeaders.get("Authorization")).toBe("Bearer test-key");
    expect(requestHeaders.get("HTTP-Referer")).toBe("https://opentvtracker.onrender.com");
    expect(requestHeaders.get("X-OpenRouter-Title")).toBe("OpenTV");
    expect(requestBody.model).toBe("anthropic/claude-sonnet-4.5");
    expect(requestBody.response_format).toMatchObject({ type: "json_schema" });
  });

  test("rejects rankings that duplicate or omit supplied candidates", async () => {
    const reranking = rerankWithOpenRouter("test-key", request, {
      model: "anthropic/claude-sonnet-4.5",
      fetcher: async () => Response.json({
        choices: [{ message: { content: JSON.stringify({ catalogIDs: [101, 101] }) } }],
      }),
    });

    await expect(reranking).rejects.toThrow("duplicate or missing candidates");
  });

  test("requires an explicit OpenRouter model", async () => {
    const reranking = rerankWithOpenRouter("test-key", request, { model: " " });

    await expect(reranking).rejects.toThrow("OPENROUTER_MODEL is not configured");
  });
});

const request: RerankRequest = {
  mood: "thoughtful",
  maximumRuntimeMinutes: 60,
  candidates: [
    {
      catalogID: 101,
      title: "First",
      genres: ["Drama"],
      runtimeMinutes: 48,
      rating: 8.1,
      providers: ["Netflix"],
      deterministicScore: 12,
      deterministicReason: "Strong match",
    },
    {
      catalogID: 202,
      title: "Second",
      genres: ["Mystery"],
      runtimeMinutes: 52,
      rating: 8.6,
      providers: ["Apple TV+"],
      deterministicScore: 11,
      deterministicReason: "Shared favorite",
    },
  ],
};
