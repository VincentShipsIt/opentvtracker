export const MediaKind = {
  movie: "movie",
  series: "series",
} as const;

export type MediaKind = (typeof MediaKind)[keyof typeof MediaKind];

export type SeriesLifecycle = "continuing" | "ended" | "unknown";

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
  alternativeTitles: string[];
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
  nextEpisodeAirDateIsAllDay: boolean | null;
  seasons: SeasonSummary[] | null;
  seriesLifecycle: SeriesLifecycle | null;
};

type StreamingProvider = {
  id: StreamingProviderID;
  name: string;
  symbol: string;
  brandHex: string | null;
};

export type CommunityReview = {
  id: string;
  author: string;
  excerpt: string;
  rating: number | null;
  source: "TMDB";
  containsSpoilers: true;
  username: string | null;
  avatarURL: string | null;
  sourceURL: string | null;
  createdAt: string | null;
  updatedAt: string | null;
};

export type CommunityReviewPage = {
  page: number;
  totalPages: number;
  results: CommunityReview[];
};

export type EpisodeSummary = {
  id: string;
  number: number;
  title: string;
  airDate: string | null;
  runtimeMinutes: number | null;
  overview: string | null;
  stillURL: string | null;
  rating: number | null;
  releaseType: "standard" | "mid_season" | "finale" | null;
  airDateIsAllDay: boolean;
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
  popularity?: number;
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
const REVIEW_ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;
const REVIEW_SOURCE_URL_PATTERN =
  /^https:\/\/www\.themoviedb\.org\/review\/([A-Za-z0-9_-]{1,128})$/;
const REVIEW_AVATAR_PATH_PATTERN =
  /^\/[A-Za-z0-9][A-Za-z0-9._-]{0,511}$/;

const DEFAULT_MAXIMUM_ACTIVE_REQUESTS = 8;
const DEFAULT_MAXIMUM_PENDING_REQUESTS = 64;
const DEFAULT_REQUEST_DEADLINE_MILLISECONDS = 8_000;
const MAXIMUM_ENRICHMENT_WORKERS = 8;
const MAXIMUM_TIMER_MILLISECONDS = 2_147_483_647;

export type TMDBFetch = (
  input: string | URL | Request,
  init?: RequestInit,
) => Promise<Response>;

export type TMDBClientOptions = {
  fetch?: TMDBFetch;
  maximumActiveRequests?: number;
  maximumPendingRequests?: number;
  requestDeadlineMilliseconds?: number;
};

export class TMDBCapacityError extends Error {
  constructor() {
    super("TMDB request capacity exhausted");
    this.name = "TMDBCapacityError";
  }
}

export class TMDBTimeoutError extends Error {
  constructor() {
    super("TMDB request timed out");
    this.name = "TMDBTimeoutError";
  }
}

type ScheduledRequest = {
  controller: AbortController;
  task: (signal: AbortSignal) => Promise<unknown>;
  resolve: (value: unknown) => void;
  reject: (error: unknown) => void;
  timer: ReturnType<typeof setTimeout> | null;
  state: "queued" | "active" | "settled";
};

/** Per-client FIFO ceiling for every TMDB fetch, including response decoding. */
class TMDBRequestScheduler {
  private activeRequests = 0;
  private readonly pendingRequests: ScheduledRequest[] = [];

  constructor(
    private readonly maximumActiveRequests: number,
    private readonly maximumPendingRequests: number,
    private readonly requestDeadlineMilliseconds: number,
  ) {}

  run<Value>(task: (signal: AbortSignal) => Promise<Value>): Promise<Value> {
    const controller = new AbortController();
    return new Promise<Value>((resolve, reject) => {
      const request: ScheduledRequest = {
        controller,
        task,
        resolve: (value: unknown) => resolve(value as Value),
        reject,
        timer: null,
        state: "queued",
      };
      // The deadline includes queueing so pending work cannot live forever.
      request.timer = setTimeout(
        () => this.expire(request),
        this.requestDeadlineMilliseconds,
      );

      if (this.activeRequests < this.maximumActiveRequests) {
        this.start(request);
      } else if (this.pendingRequests.length < this.maximumPendingRequests) {
        this.pendingRequests.push(request);
      } else {
        if (request.timer !== null) clearTimeout(request.timer);
        request.state = "settled";
        reject(new TMDBCapacityError());
      }
    });
  }

  private start(request: ScheduledRequest): void {
    if (request.state !== "queued") return;
    request.state = "active";
    this.activeRequests += 1;
    Promise.resolve()
      .then(() => request.task(request.controller.signal))
      .then(
        (value) => this.settleActive(request, true, value),
        (error: unknown) => this.settleActive(request, false, error),
      );
  }

  private expire(request: ScheduledRequest): void {
    if (request.state === "settled") return;
    const wasActive = request.state === "active";
    if (!wasActive) {
      const index = this.pendingRequests.indexOf(request);
      if (index >= 0) this.pendingRequests.splice(index, 1);
    }
    request.state = "settled";
    request.controller.abort();
    request.reject(new TMDBTimeoutError());
    if (wasActive) this.releasePermit();
  }

  private settleActive(
    request: ScheduledRequest,
    succeeded: boolean,
    result: unknown,
  ): void {
    if (request.state !== "active") return;
    if (request.timer !== null) clearTimeout(request.timer);
    request.state = "settled";
    if (succeeded) request.resolve(result);
    else request.reject(result);
    this.releasePermit();
  }

  private releasePermit(): void {
    this.activeRequests -= 1;
    while (
      this.activeRequests < this.maximumActiveRequests &&
      this.pendingRequests.length > 0
    ) {
      const next = this.pendingRequests.shift();
      if (next?.state === "queued") this.start(next);
    }
  }
}

export class TMDBClient {
  private readonly fetchImplementation: TMDBFetch;
  private readonly scheduler: TMDBRequestScheduler;

  constructor(
    private readonly token: string,
    options: TMDBClientOptions = {},
  ) {
    this.fetchImplementation = options.fetch ?? globalThis.fetch;
    this.scheduler = new TMDBRequestScheduler(
      validatedSchedulerInteger(
        options.maximumActiveRequests,
        DEFAULT_MAXIMUM_ACTIVE_REQUESTS,
        1,
        "maximumActiveRequests",
      ),
      validatedSchedulerInteger(
        options.maximumPendingRequests,
        DEFAULT_MAXIMUM_PENDING_REQUESTS,
        0,
        "maximumPendingRequests",
      ),
      validatedSchedulerInteger(
        options.requestDeadlineMilliseconds,
        DEFAULT_REQUEST_DEADLINE_MILLISECONDS,
        1,
        "requestDeadlineMilliseconds",
        MAXIMUM_TIMER_MILLISECONDS,
      ),
    );
  }

  async search(
    query: string,
    kind: MediaKind | null,
    page: number,
    region: string,
    language: string,
  ): Promise<CatalogTitle[]> {
    const locale = tmdbLocale(language);
    const items = query
      ? await this.searchItems(query, kind, page, locale)
      : await this.browseItems(kind, page, language);

    const settled = await settledMapBounded(
      items,
      MAXIMUM_ENRICHMENT_WORKERS,
      async (item) => {
        const resolvedKind = mediaKind(item.media_type);
        const namespace = resolvedKind === "movie" ? "movie" : "tv";
        const details = await this.get<Record<string, unknown>>(
          `/${namespace}/${item.id}?append_to_response=watch/providers,alternative_titles,translations&language=${locale}`,
        );
        return mapDetails(details, resolvedKind, region, null);
      },
    );
    return settled.flatMap((result) =>
      result.status === "fulfilled" ? [result.value] : [],
    );
  }

  private async searchItems(
    query: string,
    kind: MediaKind | null,
    page: number,
    locale: string,
  ): Promise<SearchItem[]> {
    const params = new URLSearchParams({
      page: String(Math.max(page, 1)),
      language: locale,
    });
    if (query) {
      params.set("query", query);
      params.set("include_adult", "false");
    }
    const payload = await this.get<{ results?: SearchItem[] }>(
      `/search/multi?${params}`,
    );
    return (payload.results ?? [])
      .filter((item) => item.media_type === "movie" || item.media_type === "tv")
      .filter((item) => !kind || mediaKind(item.media_type) === kind)
      .slice(0, 20);
  }

  private async browseItems(
    kind: MediaKind | null,
    page: number,
    language: string,
  ): Promise<SearchItem[]> {
    const requests = tmdbDiscoverRequests(language, page, kind);
    const settled = await Promise.allSettled(
      requests.map(async (request) => ({
        request,
        payload: await this.get<{ results?: SearchItem[] }>(request.path),
      })),
    );
    return settled
      .flatMap((result) => {
        if (result.status !== "fulfilled") return [];
        const { request, payload } = result.value;
        return (payload.results ?? [])
          .slice(request.resultOffset, request.resultOffset + request.resultLimit)
          .map((item) => ({
            ...item,
            media_type: request.mediaType,
          }));
      })
      .sort((left, right) => (right.popularity ?? 0) - (left.popularity ?? 0))
      .slice(0, 20);
  }

  async title(
    kind: MediaKind,
    id: number,
    region: string,
    language: string,
  ): Promise<CatalogTitle> {
    const locale = tmdbLocale(language);
    const namespace = kind === "movie" ? "movie" : "tv";
    const details = await this.get<Record<string, unknown>>(
      `/${namespace}/${id}?append_to_response=videos,watch/providers,reviews,alternative_titles,translations&language=${locale}`,
    );
    const seasons =
      kind === "series" ? await this.seasons(id, details, locale) : null;
    return mapDetails(details, kind, region, seasons);
  }

  async reviews(
    kind: MediaKind,
    id: number,
    page: number,
  ): Promise<CommunityReviewPage> {
    const namespace = kind === "movie" ? "movie" : "tv";
    const requestedPage = Math.max(page, 1);
    const payload = await this.get<Record<string, unknown>>(
      `/${namespace}/${id}/reviews?language=en-US&page=${requestedPage}`,
    );
    return mapReviewPage(payload, requestedPage);
  }

  async resolveExternalID(
    source: "tvdb",
    id: number,
    kind: MediaKind,
    region: string,
  ): Promise<CatalogTitle | null> {
    const payload = await this.get<{
      movie_results?: SearchItem[];
      tv_results?: SearchItem[];
    }>(`/find/${id}?external_source=${source}_id&language=en-US`);
    const results =
      kind === MediaKind.movie
        ? (payload.movie_results ?? [])
        : (payload.tv_results ?? []);
    const matchingIDs = [
      ...new Set(
        results
          .map((result) => result.id)
          .filter((value): value is number => Number.isSafeInteger(value)),
      ),
    ];
    if (matchingIDs.length !== 1) return null;
    return this.title(kind, matchingIDs[0]!, region, "en");
  }

  private async seasons(
    showID: number,
    details: Record<string, unknown>,
    locale: string,
  ): Promise<SeasonSummary[]> {
    const listedSeasons = Array.isArray(details.seasons) ? details.seasons : [];
    const seasonNumbers = [
      ...new Set(
        listedSeasons
          .map((value) => asRecord(value))
          .map((season) => numberValue(season.season_number))
          .filter(
            (number): number is number =>
              number !== null && Number.isSafeInteger(number) && number >= 0,
          ),
      ),
    ];

    const settled = await settledMapBounded(
      seasonNumbers,
      MAXIMUM_ENRICHMENT_WORKERS,
      (number) =>
        this.get<Record<string, unknown>>(
          `/tv/${showID}/season/${number}?language=${locale}`,
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
    return this.scheduler.run(async (signal) => {
      const response = await this.fetchImplementation(`${API_URL}${path}`, {
        headers: {
          Accept: "application/json",
          Authorization: `Bearer ${this.token}`,
          "User-Agent": "OpenTVTracker/0.1",
        },
        signal,
      });
      if (!response.ok) throw new Error(`TMDB returned ${response.status}`);
      return response.json() as Promise<Response>;
    });
  }
}

async function settledMapBounded<Input, Output>(
  values: readonly Input[],
  maximumWorkers: number,
  transform: (value: Input, index: number) => Promise<Output>,
): Promise<PromiseSettledResult<Output>[]> {
  const results = new Array<PromiseSettledResult<Output>>(values.length);
  let nextIndex = 0;
  const worker = async (): Promise<void> => {
    while (nextIndex < values.length) {
      const index = nextIndex;
      nextIndex += 1;
      try {
        results[index] = {
          status: "fulfilled",
          value: await transform(values[index]!, index),
        };
      } catch (reason) {
        results[index] = { status: "rejected", reason };
      }
    }
  };
  const workers = Array.from(
    { length: Math.min(maximumWorkers, values.length) },
    () => worker(),
  );
  await Promise.all(workers);
  return results;
}

export function tmdbLocale(language: string): string {
  const locale = new Intl.Locale(language).maximize();
  return locale.region
    ? `${locale.language}-${locale.region}`
    : locale.language;
}

export function tmdbDiscoverRequests(
  language: string,
  page: number,
  kind: MediaKind | null,
): Array<{
  mediaType: "movie" | "tv";
  path: string;
  resultOffset: number;
  resultLimit: number;
}> {
  const locale = tmdbLocale(language);
  const requestedPage = Math.max(page, 1);
  const mediaTypes: Array<"movie" | "tv"> =
    kind === MediaKind.movie
      ? ["movie"]
      : kind === MediaKind.series
        ? ["tv"]
        : ["movie", "tv"];
  const mixesMediaTypes = mediaTypes.length > 1;
  const providerPage = mixesMediaTypes
    ? Math.floor((requestedPage - 1) / 2) + 1
    : requestedPage;
  const resultOffset = mixesMediaTypes
    ? ((requestedPage - 1) % 2) * 10
    : 0;
  const resultLimit = mixesMediaTypes ? 10 : 20;

  return mediaTypes.map((mediaType) => {
    const params = new URLSearchParams({
      page: String(providerPage),
      language: locale,
      sort_by: "popularity.desc",
      include_adult: "false",
      with_original_language: language,
    });
    return {
      mediaType,
      path: `/discover/${mediaType}?${params}`,
      resultOffset,
      resultLimit,
    };
  });
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
    alternativeTitles: mapAlternativeTitles(details, kind),
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
    nextEpisodeAirDateIsAllDay: stringValue(nextEpisode.air_date) !== null,
    seasons,
    seriesLifecycle:
      kind === MediaKind.series ? mapSeriesLifecycle(details.status) : null,
  };
}

export function mapAlternativeTitles(
  details: Record<string, unknown>,
  kind: MediaKind,
): string[] {
  const values: unknown[] = [
    kind === MediaKind.movie ? details.original_title : details.original_name,
  ];
  const translations = asRecord(details.translations);
  for (const item of Array.isArray(translations.translations)
    ? translations.translations
    : []) {
    const data = asRecord(asRecord(item).data);
    values.push(data.title, data.name);
  }
  const alternatives = asRecord(details.alternative_titles);
  const alternativeItems = Array.isArray(alternatives.titles)
    ? alternatives.titles
    : Array.isArray(alternatives.results)
      ? alternatives.results
      : [];
  for (const item of alternativeItems) {
    const value = asRecord(item);
    values.push(value.title, value.name);
  }

  const primaryTitle = stringValue(
    kind === MediaKind.movie ? details.title : details.name,
  );
  const seen = new Set(primaryTitle ? [normalizedTitle(primaryTitle)] : []);
  return values
    .flatMap((value) => {
      const title = stringValue(value)?.replace(/\s+/g, " ").trim();
      if (!title || title.length > 200) return [];
      const normalized = normalizedTitle(title);
      if (seen.has(normalized)) return [];
      seen.add(normalized);
      return [title];
    })
    .slice(0, 50);
}

export function mapSeriesLifecycle(status: unknown): SeriesLifecycle {
  if (typeof status !== "string") return "unknown";
  switch (status.toLowerCase()) {
    case "ended":
    case "canceled":
      return "ended";
    case "returning series":
    case "in production":
    case "planned":
    case "pilot":
      return "continuing";
    default:
      return "unknown";
  }
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
    rating: numberValue(episode.vote_average),
    releaseType: episodeReleaseType(episode.episode_type),
    airDateIsAllDay: true,
  };
}

export function mapReviewPage(
  payload: Record<string, unknown>,
  requestedPage: number,
): CommunityReviewPage {
  const page = boundedInteger(requestedPage, 1, 1, 100);
  const rawTotalPages = numberValue(payload.total_pages);
  const totalPages =
    rawTotalPages !== null && Number.isSafeInteger(rawTotalPages)
      ? Math.min(Math.max(rawTotalPages, page), 100)
      : page;
  return {
    page,
    totalPages,
    results: mapReviews(payload, page, 20),
  };
}

function episodeReleaseType(
  value: unknown,
): "standard" | "mid_season" | "finale" | null {
  if (value === "standard" || value === "mid_season" || value === "finale") {
    return value;
  }
  return null;
}

export function mapReviews(
  payload: Record<string, unknown>,
  page = 1,
  maximum = 8,
): CommunityReview[] {
  return (Array.isArray(payload.results) ? payload.results : [])
    .slice(0, maximum)
    .map((value, index): CommunityReview => {
      const review = asRecord(value);
      const authorDetails = asRecord(review.author_details);
      const content =
        stringValue(review.content)?.replace(/\s+/g, " ").trim() ?? "";
      const providerID = reviewID(stringValue(review.id));
      return {
        id: providerID
          ? `tmdb-review-provider-${providerID}`
          : `tmdb-review-fallback-${page}-${index}`,
        author: stringValue(review.author) ?? "TMDB member",
        excerpt: content,
        rating: numberValue(authorDetails.rating),
        source: "TMDB",
        containsSpoilers: true,
        username: stringValue(authorDetails.username),
        avatarURL: reviewAvatarURL(stringValue(authorDetails.avatar_path)),
        sourceURL: reviewSourceURL(providerID, stringValue(review.url)),
        createdAt: isoTimestamp(stringValue(review.created_at)),
        updatedAt: isoTimestamp(stringValue(review.updated_at)),
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

function reviewAvatarURL(path: string | null): string | null {
  return path && REVIEW_AVATAR_PATH_PATTERN.test(path)
    ? `${IMAGE_URL}/w185${path}`
    : null;
}

function reviewID(value: string | null): string | null {
  return value && REVIEW_ID_PATTERN.test(value) ? value : null;
}

function reviewSourceURL(
  providerID: string | null,
  upstreamURL: string | null,
): string | null {
  if (providerID) {
    return `https://www.themoviedb.org/review/${providerID}`;
  }
  const fallbackID = upstreamURL?.match(REVIEW_SOURCE_URL_PATTERN)?.[1] ?? null;
  return fallbackID
    ? `https://www.themoviedb.org/review/${fallbackID}`
    : null;
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

function isoTimestamp(value: string | null): string | null {
  if (!value) return null;
  const timestamp = new Date(value);
  if (Number.isNaN(timestamp.valueOf())) return null;
  return timestamp.toISOString().replace(/\.\d{3}Z$/, "Z");
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

function boundedInteger(
  value: unknown,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  const parsed = numberValue(value);
  return parsed !== null &&
    Number.isSafeInteger(parsed) &&
    parsed >= minimum &&
    parsed <= maximum
    ? parsed
    : fallback;
}

function validatedSchedulerInteger(
  value: number | undefined,
  fallback: number,
  minimum: number,
  name: string,
  maximum = Number.MAX_SAFE_INTEGER,
): number {
  if (value === undefined) return fallback;
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    throw new RangeError(
      `${name} must be a safe integer between ${minimum} and ${maximum}`,
    );
  }
  return value;
}

function normalizedTitle(value: string): string {
  return value.normalize("NFKD").toLocaleLowerCase("en-US");
}
