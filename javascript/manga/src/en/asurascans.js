const mangayomiSources = [
	{
		id: 524070078,
		name: "Asura Scans",
		lang: "en",
		baseUrl: "https://asurascans.com",
		apiUrl: "https://api.asurascans.com",
		iconUrl:
			"https://raw.githubusercontent.com/MorningOctober/manga-extensions/main/javascript/icon/en.asurascans.png",
		typeSource: "single",
		itemType: 0,
		version: "0.2.8",
		dateFormat: "",
		dateFormatLocale: "",
		pkgPath: "manga/src/en/asurascans.js",
	},
];

class DefaultExtension extends MProvider {
	_trimTrailingSlash(url) {
		return String(url || "")
			.trim()
			.replace(/\/+$/, "");
	}

	_normalizeSitePath(path, fallback = "/") {
		const raw = String(path || "").trim();
		if (!raw) return fallback;
		if (/^https?:\/\//i.test(raw)) {
			return raw;
		}
		return raw.startsWith("/") ? raw : `/${raw}`;
	}

	_parseJsonBody(body, context) {
		const raw = String(body || "").trim();
		try {
			return JSON.parse(raw);
		} catch (_err) {
			const firstObj = raw.indexOf("{");
			const firstArr = raw.indexOf("[");
			const first =
				firstObj === -1
					? firstArr
					: firstArr === -1
						? firstObj
						: Math.min(firstObj, firstArr);
			const lastObj = raw.lastIndexOf("}");
			const lastArr = raw.lastIndexOf("]");
			const last = Math.max(lastObj, lastArr);

			if (first !== -1 && last !== -1 && last > first) {
				const candidate = raw.slice(first, last + 1);
				try {
					return JSON.parse(candidate);
				} catch (_err2) {}
			}
			throw new Error(`Invalid JSON response in ${context}`);
		}
	}

	getHeaders(_url) {
		return { Referer: this.siteBase };
	}

	get apiBase() {
		return this._trimTrailingSlash(
			new SharedPreferences().get("overrideApiUrl") || this.source.apiUrl,
		);
	}

	get siteBase() {
		return this._trimTrailingSlash(
			new SharedPreferences().get("overrideSiteUrl") || this.source.baseUrl,
		);
	}

	// Supports: "/comics/foo-f6174291", "https://.../comics/foo-f6174291", "/series/foo", "foo"
	_slugFromUrl(url) {
		const raw = String(url || "").trim();
		if (!raw) throw new Error("Missing manga URL");
		if (raw.includes("||")) return raw.split("||")[0];

		let path = raw
			.replace(/^https?:\/\/[^/]+/i, "")
			.split("?")[0]
			.split("#")[0];
		path = path.replace(/^\/+/, "").replace(/\/+$/, "");

		const routeMatch = path.match(/(?:^|\/)(?:comics|series)\/([^/]+)/i);
		if (routeMatch?.[1]) {
			return routeMatch[1].replace(/-f[0-9a-f]{6,8}$/i, "");
		}

		const singleSegment = path.split("/").filter(Boolean);
		if (singleSegment.length === 1) {
			return singleSegment[0].replace(/-f[0-9a-f]{6,8}$/i, "");
		}

		throw new Error(`Unable to parse series slug from URL: ${url}`);
	}

	_chapterRefFromUrl(url) {
		const raw = String(url || "").trim();
		if (!raw) throw new Error("Missing chapter URL");

		if (raw.includes("||")) {
			const [seriesSlug, chapterSlug] = raw.split("||");
			return { seriesSlug, chapterSlug };
		}

		let path = raw
			.replace(/^https?:\/\/[^/]+/i, "")
			.split("?")[0]
			.split("#")[0];
		path = path.replace(/^\/+/, "").replace(/\/+$/, "");
		const parts = path.split("/").filter(Boolean);

		if (
			parts.length >= 3 &&
			(parts[0] === "comics" || parts[0] === "series") &&
			parts[1]
		) {
			return {
				seriesSlug: parts[1].replace(/-f[0-9a-f]{6,8}$/i, ""),
				chapterSlug: parts[parts.length - 1],
			};
		}

		throw new Error(`Unable to parse chapter URL: ${url}`);
	}

	_parseMangaList(json) {
		const items = json.data || [];
		const meta = json.meta || {};
		const list = items.map((item) => ({
			name: item.title || item.name || "",
			imageUrl: item.cover || item.cover_url || "",
			link: this._normalizeSitePath(
				item.public_url || (item.slug ? `/comics/${item.slug}` : ""),
				"/",
			),
		}));
		return { list, hasNextPage: meta.has_more === true };
	}

	toStatus(status) {
		switch ((status || "").toLowerCase()) {
			case "ongoing":
				return 0;
			case "completed":
				return 1;
			case "hiatus":
			case "seasonal":
				return 2;
			case "dropped":
				return 3;
			default:
				return 5;
		}
	}

	parseDate(dateStr) {
		if (!dateStr) return null;
		const ts = Date.parse(dateStr);
		return Number.isNaN(ts) ? null : String(ts);
	}

	async getPopular(page) {
		const offset = (page - 1) * 20;
		const res = await new Client().get(
			`${this.apiBase}/api/series?sort=rating&order=desc&offset=${offset}&limit=20`,
		);
		return this._parseMangaList(this._parseJsonBody(res.body, "getPopular"));
	}

	async getLatestUpdates(page) {
		const offset = (page - 1) * 20;
		const res = await new Client().get(
			`${this.apiBase}/api/series?sort=latest&order=desc&offset=${offset}&limit=20`,
		);
		return this._parseMangaList(
			this._parseJsonBody(res.body, "getLatestUpdates"),
		);
	}

	async search(query, page, filters) {
		const q = encodeURIComponent(query || "");
		const offset = (page - 1) * 20;
		const safeFilters = Array.isArray(filters) ? filters : [];

		const selectValue = (index, fallback) => {
			const filter = safeFilters[index];
			if (!filter || !Array.isArray(filter.values)) return fallback;
			const selected = filter.values[filter.state];
			if (!selected || selected.value == null) return fallback;
			return selected.value;
		};

		const sortBy = selectValue(0, "rating");
		const sortDir = selectValue(1, "desc");
		const status = selectValue(2, "");
		const type = selectValue(3, "");
		const genreFilter = safeFilters[4];
		const genres = Array.isArray(genreFilter?.state)
			? genreFilter.state
					.filter((cb) => cb.state)
					.map((cb) => cb.value)
					.join(",")
			: "";

		let url = `${this.apiBase}/api/series?offset=${offset}&limit=20&sort=${sortBy}&order=${sortDir}`;
		if (q) url += `&search=${q}`;
		if (status) url += `&status=${status}`;
		if (type) url += `&type=${type}`;
		if (genres) url += `&genres=${encodeURIComponent(genres)}`;

		const res = await new Client().get(url);
		return this._parseMangaList(this._parseJsonBody(res.body, "search"));
	}

	getFilterList() {
		return [
			{
				type_name: "SelectFilter",
				name: "Sort By",
				state: 0,
				values: [
					{ type_name: "SelectOption", name: "Rating", value: "rating" },
					{
						type_name: "SelectOption",
						name: "Latest Update",
						value: "latest",
					},
				],
			},
			{
				type_name: "SelectFilter",
				name: "Sort Order",
				state: 1,
				values: [
					{ type_name: "SelectOption", name: "Ascending", value: "asc" },
					{ type_name: "SelectOption", name: "Descending", value: "desc" },
				],
			},
			{
				type_name: "SelectFilter",
				name: "Status",
				state: 0,
				values: [
					{ type_name: "SelectOption", name: "All", value: "" },
					{ type_name: "SelectOption", name: "Ongoing", value: "ongoing" },
					{
						type_name: "SelectOption",
						name: "Completed",
						value: "completed",
					},
					{ type_name: "SelectOption", name: "Hiatus", value: "hiatus" },
					{
						type_name: "SelectOption",
						name: "Seasonal",
						value: "seasonal",
					},
					{ type_name: "SelectOption", name: "Dropped", value: "dropped" },
				],
			},
			{
				type_name: "SelectFilter",
				name: "Type",
				state: 0,
				values: [
					{ type_name: "SelectOption", name: "All", value: "" },
					{ type_name: "SelectOption", name: "Manhwa", value: "manhwa" },
					{ type_name: "SelectOption", name: "Manga", value: "manga" },
					{ type_name: "SelectOption", name: "Manhua", value: "manhua" },
				],
			},
			{
				type_name: "GroupFilter",
				name: "Genres",
				state: [
					{ type_name: "CheckBox", name: "Action", value: "action" },
					{ type_name: "CheckBox", name: "Adventure", value: "adventure" },
					{ type_name: "CheckBox", name: "Comedy", value: "comedy" },
					{ type_name: "CheckBox", name: "Crazy MC", value: "crazy-mc" },
					{ type_name: "CheckBox", name: "Demon", value: "demon" },
					{ type_name: "CheckBox", name: "Dungeons", value: "dungeons" },
					{ type_name: "CheckBox", name: "Fantasy", value: "fantasy" },
					{ type_name: "CheckBox", name: "Game", value: "game" },
					{ type_name: "CheckBox", name: "Genius MC", value: "genius-mc" },
					{ type_name: "CheckBox", name: "Isekai", value: "isekai" },
					{ type_name: "CheckBox", name: "Kuchikuchi", value: "kuchikuchi" },
					{ type_name: "CheckBox", name: "Magic", value: "magic" },
					{
						type_name: "CheckBox",
						name: "Martial Arts",
						value: "martial-arts",
					},
					{ type_name: "CheckBox", name: "Murim", value: "murim" },
					{ type_name: "CheckBox", name: "Mystery", value: "mystery" },
					{
						type_name: "CheckBox",
						name: "Necromancer",
						value: "necromancer",
					},
					{
						type_name: "CheckBox",
						name: "Overpowered",
						value: "overpowered",
					},
					{ type_name: "CheckBox", name: "Regression", value: "regression" },
					{
						type_name: "CheckBox",
						name: "Reincarnation",
						value: "reincarnation",
					},
					{ type_name: "CheckBox", name: "Revenge", value: "revenge" },
					{ type_name: "CheckBox", name: "Romance", value: "romance" },
					{
						type_name: "CheckBox",
						name: "School Life",
						value: "school-life",
					},
					{ type_name: "CheckBox", name: "Sci-fi", value: "sci-fi" },
					{ type_name: "CheckBox", name: "Shoujo", value: "shoujo" },
					{ type_name: "CheckBox", name: "Shounen", value: "shounen" },
					{ type_name: "CheckBox", name: "System", value: "system" },
					{ type_name: "CheckBox", name: "Tower", value: "tower" },
					{ type_name: "CheckBox", name: "Tragedy", value: "tragedy" },
					{ type_name: "CheckBox", name: "Villain", value: "villain" },
					{ type_name: "CheckBox", name: "Violence", value: "violence" },
				],
			},
		];
	}

	async getDetail(url) {
		const slug = this._slugFromUrl(url);

		const seriesRes = await new Client().get(
			`${this.apiBase}/api/series/${slug}`,
		);
		const seriesJson = this._parseJsonBody(seriesRes.body, "getDetail-series");
		const s = seriesJson.series || seriesJson;

		const description = (s.description || "").replace(/<[^>]+>/g, "").trim(); // HTML strip
		const imageUrl = s.cover || s.cover_url || "";
		const seriesPublicUrl = this._normalizeSitePath(
			s.public_url || `/comics/${slug}`,
			`/comics/${slug}`,
		);
		const author = s.author || "";
		const artist = s.artist || "";
		const status = this.toStatus(s.status);
		const genre = (s.genres || []).map((g) => g.name);

		// paginated chapter fetch
		const allChaps = [];
		let pageNum = 1;
		const limit = 100;
		while (true) {
			const chapRes = await new Client().get(
				`${this.apiBase}/api/series/${slug}/chapters?page=${pageNum}&limit=${limit}`,
			);
			const pageJson = this._parseJsonBody(
				chapRes.body,
				`getDetail-chapters-page-${pageNum}`,
			);
			const pageData = pageJson.data || [];
			allChaps.push(...pageData);
			if (pageData.length < limit) break;
			pageNum++;
		}

		// chapter url is a web path so WebView can open it directly
		const chapters = allChaps
			.filter((ch) => !ch.is_locked)
			.map((ch) => {
				const chapterLabel =
					ch.number != null ? `Chapter ${ch.number}` : "Chapter";
				const chapterTitle = (ch.title || "").trim();
				return {
					name: chapterTitle
						? `${chapterLabel} - ${chapterTitle}`
						: chapterLabel,
					url: `${seriesPublicUrl}/chapter/${ch.slug}`,
					dateUpload: this.parseDate(ch.published_at),
				};
			});

		return { imageUrl, description, genre, author, artist, status, chapters };
	}

	async getPageList(url) {
		const { seriesSlug, chapterSlug } = this._chapterRefFromUrl(url);

		const res = await new Client().get(
			`${this.apiBase}/api/series/${seriesSlug}/chapters/${chapterSlug}`,
		);
		const json = this._parseJsonBody(res.body, "getPageList");
		const chapter = json.data?.chapter ? json.data.chapter : json;
		const pages = chapter.pages || [];

		const pageList = pages
			.map((p, i) =>
				typeof p === "string"
					? { url: p, order: i }
					: { url: p.url, order: p.order != null ? p.order : i },
			)
			.filter((p) => !!p.url)
			.sort((a, b) => a.order - b.order)
			.map((p) => p.url);

		if (pageList.length === 0) {
			throw new Error("No readable pages found for this chapter");
		}

		return pageList;
	}

	getSourcePreferences() {
		return [
			{
				key: "overrideSiteUrl",
				editTextPreference: {
					title: "Override Site URL",
					summary: "https://asurascans.com",
					value: "https://asurascans.com",
					dialogTitle: "Override Site URL",
					dialogMessage: "",
				},
			},
			{
				key: "overrideApiUrl",
				editTextPreference: {
					title: "Override API URL",
					summary: "https://api.asurascans.com",
					value: "https://api.asurascans.com",
					dialogTitle: "Override API URL",
					dialogMessage: "",
				},
			},
		];
	}
}
