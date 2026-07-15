export const MediaKind = {
  movie: "movie",
  series: "series",
} as const;

export type MediaKind = (typeof MediaKind)[keyof typeof MediaKind];

export const StreamingProviderID = {
  netflix: "netflix",
  primeVideo: "prime-video",
  appleTV: "apple-tv",
  disneyPlus: "disney-plus",
  max: "max",
  mubi: "mubi",
  paramount: "paramount",
} as const;

export type StreamingProviderID =
  (typeof StreamingProviderID)[keyof typeof StreamingProviderID];

export const TMDBProviderID = {
  netflix: 8,
  netflixKids: 175,
  netflixWithAds: 1796,
  primeVideoLegacy: 9,
  primeVideo: 119,
  primeVideoWithAds: 2100,
  appleTV: 350,
  disneyPlusLegacy: 122,
  disneyPlus: 337,
  mubi: 11,
  max: 1899,
  paramountPlus: 531,
  paramountPremium: 2303,
  paramountWithAds: 2304,
  paramountEssential: 2616,
} as const;

export type CatalogTitle = {
  catalogID: number;
  title: string;
  year: number;
  kind: MediaKind;
  synopsis: string;
  genres: string[];
  runtimeMinutes: number;
  rating: number;
  mood: "any" | "cozy" | "funny" | "intense" | "thoughtful";
  posterURL: string | null;
  backdropURL: string | null;
  trailerURL: string | null;
  providers: StreamingProvider[];
  reviews: CommunityReview[];
  releaseDate: string | null;
  nextEpisodeAirDate: string | null;
  seasons: SeasonSummary[] | null;
};

type StreamingProvider = {
  id: StreamingProviderID;
  name: string;
  symbol: string;
  brandHex: string | null;
};

type CommunityReview = {
  id: string;
  author: string;
  excerpt: string;
  rating: number | null;
  source: "TMDB";
  containsSpoilers: true;
};

export type EpisodeSummary = {
  id: string;
  number: number;
  title: string;
  airDate: string | null;
  runtimeMinutes: number | null;
  overview: string | null;
  stillURL: string | null;
};

type SeasonSummary = {
  id: string;
  number: number;
  title: string;
  episodes: EpisodeSummary[];
};

type SearchItem = {
  id: number;
  media_type?: "movie" | "tv" | "person";
  title?: string;
  name?: string;
  overview?: string;
  genre_ids?: number[];
  release_date?: string;
  first_air_date?: string;
  vote_average?: number;
  poster_path?: string | null;
  backdrop_path?: string | null;
};

type TMDBProvider = { provider_id?: unknown };
type ProviderPayload = {
  results?: Record<string, { flatrate?: TMDBProvider[]; link?: string }>;
};

const API_URL = "https://api.themoviedb.org/3";
const IMAGE_URL = "https://image.tmdb.org/t/p";

export class TMDBClient {
  constructor(private readonly token: string) {}

  async search(
    query: string,
    kind: MediaKind | null,
    page: number,
    region: string,
  ): Promise<CatalogTitle[]> {
    const path = query ? "/search/multi" : "/trending/all/week";
    const params = new URLSearchParams({
      page: String(Math.max(page, 1)),
      language: "en-US",
    });
    if (query) {
      params.set("query", query);
      params.set("include_adult", "false");
    }
    const payload = await this.get<{ results?: SearchItem[] }>(
      `${path}?${params}`,
    );
    const items = (payload.results ?? [])
      .filter((item) => item.media_type === "movie" || item.media_type === "tv")
      .filter((item) => !kind || mediaKind(item.media_type) === kind)
      .slice(0, 20);

    const settled = await Promise.allSettled(
      items.map(async (item) => {
        const resolvedKind = mediaKind(item.media_type);
        const namespace = resolvedKind === "movie" ? "movie" : "tv";
        const details = await this.get<Record<string, unknown>>(
          `/${namespace}/${item.id}?append_to_response=watch/providers&language=en-US`,
        );
        return mapDetails(details, resolvedKind, region, null);
      }),
    );
    return settled.flatMap((result) =>
      result.status === "fulfilled" ? [result.value] : [],
    );
  }

  async title(
    kind: MediaKind,
    id: number,
    region: string,
  ): Promise<CatalogTitle> {
    const namespace = kind === "movie" ? "movie" : "tv";
    const details = await this.get<Record<string, unknown>>(
      `/${namespace}/${id}?append_to_response=videos,watch/providers,reviews&language=en-US`,
    );
    const seasons = kind === "series" ? await this.seasons(id, details) : null;
    return mapDetails(details, kind, region, seasons);
  }

  private async seasons(
    showID: number,
    details: Record<string, unknown>,
  ): Promise<SeasonSummary[]> {
    const listedSeasons = Array.isArray(details.seasons) ? details.seasons : [];
    const seasonNumbers = listedSeasons
      .map((value) => asRecord(value))
      .map((season) => numberValue(season.season_number))
      .filter((number): number is number => number !== null);

    const settled = await Promise.allSettled(
      seasonNumbers.map((number) =>
        this.get<Record<string, unknown>>(
          `/tv/${showID}/season/${number}?language=en-US`,
        ),
      ),
    );
    return settled
      .flatMap((result) => {
        if (result.status !== "fulfilled") return [];
        const season = result.value;
        const number = numberValue(season.season_number) ?? 0;
        const episodes = Array.isArray(season.episodes) ? season.episodes : [];
        return [
          {
            id: `tmdb-season-${showID}-${number}`,
            number,
            title:
              stringValue(season.name) ??
              (number === 0 ? "Specials" : `Season ${number}`),
            episodes: episodes.map((value) =>
              mapEpisodeSummary(value, showID, number),
            ),
          },
        ];
      })
      .sort((left, right) => left.number - right.number);
  }

  private async get<Response>(path: string): Promise<Response> {
    const response = await fetch(`${API_URL}${path}`, {
      headers: {
        Accept: "application/json",
        Authorization: `Bearer ${this.token}`,
        "User-Agent": "OpenTVTracker/0.1",
      },
      signal: AbortSignal.timeout(8_000),
    });
    if (!response.ok) throw new Error(`TMDB returned ${response.status}`);
    return response.json() as Promise<Response>;
  }
}

function mapDetails(
  details: Record<string, unknown>,
  kind: MediaKind,
  region: string,
  seasons: SeasonSummary[] | null,
): CatalogTitle {
  const genres = (Array.isArray(details.genres) ? details.genres : [])
    .map((value) => stringValue(asRecord(value).name))
    .filter((value): value is string => Boolean(value));
  const releaseDay = stringValue(
    kind === "movie" ? details.release_date : details.first_air_date,
  );
  const videos = asRecord(details.videos);
  const trailer =
    (Array.isArray(videos.results) ? videos.results : [])
      .map(asRecord)
      .find(
        (video) =>
          video.site === "YouTube" &&
          video.type === "Trailer" &&
          video.official === true,
      ) ??
    (Array.isArray(videos.results) ? videos.results : [])
      .map(asRecord)
      .find((video) => video.site === "YouTube" && video.type === "Trailer");
  const providerPayload = asRecord(
    details["watch/providers"],
  ) as ProviderPayload;
  const reviewsPayload = asRecord(details.reviews);
  const nextEpisode = asRecord(details.next_episode_to_air);
  const runtime =
    kind === "movie"
      ? numberValue(details.runtime)
      : Array.isArray(details.episode_run_time)
        ? details.episode_run_time
            .map(numberValue)
            .find((value): value is number => value !== null)
        : null;

  return {
    catalogID: numberValue(details.id) ?? 0,
    title:
      stringValue(kind === "movie" ? details.title : details.name) ??
      "Untitled",
    year: yearFromDay(releaseDay),
    kind,
    synopsis:
      stringValue(details.overview)?.trim() ||
      "No synopsis has been published yet.",
    genres,
    runtimeMinutes: runtime ?? 0,
    rating: numberValue(details.vote_average) ?? 0,
    mood: moodFor(genres),
    posterURL: imageURL(stringValue(details.poster_path), "w780"),
    backdropURL: imageURL(stringValue(details.backdrop_path), "w1280"),
    trailerURL: trailer ? youtubeURL(stringValue(trailer.key)) : null,
    providers: providersForRegion(providerPayload, region),
    reviews: mapReviews(reviewsPayload),
    releaseDate: isoDay(releaseDay),
    nextEpisodeAirDate: isoDay(stringValue(nextEpisode.air_date)),
    seasons,
  };
}

function providersForRegion(
  payload: ProviderPayload,
  region: string,
): StreamingProvider[] {
  const entries = payload.results?.[region]?.flatrate ?? [];
  const providers = entries.flatMap((entry) =>
    mapStreamingProvider(entry.provider_id),
  );
  return [...new Map(providers.map((value) => [value.id, value])).values()];
}

const providerMetadata = {
  [StreamingProviderID.netflix]: {
    name: "Netflix",
    symbol: "n.square.fill",
    brandHex: "E50914",
  },
  [StreamingProviderID.primeVideo]: {
    name: "Prime Video",
    symbol: "play.rectangle.fill",
    brandHex: "00A8E1",
  },
  [StreamingProviderID.appleTV]: {
    name: "Apple TV+",
    symbol: "apple.logo",
    brandHex: "1C1C1E",
  },
  [StreamingProviderID.disneyPlus]: {
    name: "Disney+",
    symbol: "sparkles.tv",
    brandHex: "113CCF",
  },
  [StreamingProviderID.max]: {
    name: "Max",
    symbol: "play.tv",
    brandHex: "5822B4",
  },
  [StreamingProviderID.mubi]: {
    name: "MUBI",
    symbol: "m.circle",
    brandHex: "1976D2",
  },
  [StreamingProviderID.paramount]: {
    name: "Paramount+",
    symbol: "mountain.2",
    brandHex: "0064FF",
  },
} satisfies Record<StreamingProviderID, Omit<StreamingProvider, "id">>;

const providerIDByTMDBID: Readonly<
  Partial<Record<number, StreamingProviderID>>
> = {
  [TMDBProviderID.netflix]: StreamingProviderID.netflix,
  [TMDBProviderID.netflixKids]: StreamingProviderID.netflix,
  [TMDBProviderID.netflixWithAds]: StreamingProviderID.netflix,
  [TMDBProviderID.primeVideoLegacy]: StreamingProviderID.primeVideo,
  [TMDBProviderID.primeVideo]: StreamingProviderID.primeVideo,
  [TMDBProviderID.primeVideoWithAds]: StreamingProviderID.primeVideo,
  [TMDBProviderID.appleTV]: StreamingProviderID.appleTV,
  [TMDBProviderID.disneyPlusLegacy]: StreamingProviderID.disneyPlus,
  [TMDBProviderID.disneyPlus]: StreamingProviderID.disneyPlus,
  [TMDBProviderID.mubi]: StreamingProviderID.mubi,
  [TMDBProviderID.max]: StreamingProviderID.max,
  [TMDBProviderID.paramountPlus]: StreamingProviderID.paramount,
  [TMDBProviderID.paramountPremium]: StreamingProviderID.paramount,
  [TMDBProviderID.paramountWithAds]: StreamingProviderID.paramount,
  [TMDBProviderID.paramountEssential]: StreamingProviderID.paramount,
};

export function mapStreamingProvider(providerID: unknown): StreamingProvider[] {
  if (typeof providerID !== "number" || !Number.isSafeInteger(providerID))
    return [];
  const id: StreamingProviderID | undefined = providerIDByTMDBID[providerID];
  return id ? [{ id, ...providerMetadata[id] }] : [];
}

export function mapEpisodeSummary(
  value: unknown,
  showID: number,
  seasonNumber: number,
): EpisodeSummary {
  const episode = asRecord(value);
  const episodeNumber = numberValue(episode.episode_number) ?? 0;
  return {
    id: `tmdb-episode-${numberValue(episode.id) ?? `${showID}-${seasonNumber}-${episodeNumber}`}`,
    number: episodeNumber,
    title: stringValue(episode.name) ?? `Episode ${episodeNumber}`,
    airDate: isoDay(stringValue(episode.air_date)),
    runtimeMinutes: numberValue(episode.runtime),
    overview: stringValue(episode.overview)?.trim() || null,
    stillURL: imageURL(stringValue(episode.still_path), "w500"),
  };
}

function mapReviews(payload: Record<string, unknown>): CommunityReview[] {
  return (Array.isArray(payload.results) ? payload.results : [])
    .slice(0, 8)
    .map((value, index): CommunityReview => {
      const review = asRecord(value);
      const authorDetails = asRecord(review.author_details);
      const content =
        stringValue(review.content)?.replace(/\s+/g, " ").trim() ?? "";
      return {
        id: `tmdb-review-${stringValue(review.id) ?? index}`,
        author: stringValue(review.author) ?? "TMDB member",
        excerpt: content.length > 600 ? `${content.slice(0, 597)}…` : content,
        rating: numberValue(authorDetails.rating),
        source: "TMDB",
        containsSpoilers: true,
      };
    })
    .filter((review) => review.excerpt.length > 0);
}

function mediaKind(value: "movie" | "tv" | "person" | undefined): MediaKind {
  return value === "movie" ? MediaKind.movie : MediaKind.series;
}

function moodFor(genres: string[]): CatalogTitle["mood"] {
  const values = new Set(genres.map((genre) => genre.toLowerCase()));
  if (values.has("comedy")) return "funny";
  if (
    ["horror", "thriller", "action", "crime"].some((value) => values.has(value))
  )
    return "intense";
  if (["drama", "documentary", "history"].some((value) => values.has(value)))
    return "thoughtful";
  if (["family", "romance"].some((value) => values.has(value))) return "cozy";
  return "any";
}

function imageURL(
  path: string | null | undefined,
  size: string,
): string | null {
  return path ? `${IMAGE_URL}/${size}${path}` : null;
}

function youtubeURL(key: string | null): string | null {
  return key
    ? `https://www.youtube.com/watch?v=${encodeURIComponent(key)}`
    : null;
}

function yearFromDay(value: string | null | undefined): number {
  const year = Number(value?.slice(0, 4));
  return Number.isFinite(year) ? year : 0;
}

function isoDay(value: string | null | undefined): string | null {
  return value && /^\d{4}-\d{2}-\d{2}$/.test(value)
    ? `${value}T00:00:00Z`
    : null;
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object"
    ? (value as Record<string, unknown>)
    : {};
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function numberValue(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}
