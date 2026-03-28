const mangayomiSources = [
	{
		"id": 774494992,
		"name": "Genz Updates",
		"lang": "en",
		"baseUrl": "https://genzupdates.com",
		"apiUrl": "",
		"iconUrl":
			"https://raw.githubusercontent.com/MorningOctober/manga-extensions/main/javascript/icon/en.genzupdates.png",
		"typeSource": "single",
		"itemType": 0,
		"version": "0.0.8",
		"dateFormat": "MMM d, yyyy",
		"dateFormatLocale": "en",
		"hasCloudflare": true,
		"pkgPath": "manga/src/en/genzupdates.js"
	}
];

class DefaultExtension extends MProvider {
	constructor(...args) {
		super(...args);
		// Keep default client stack so Mangayomi's Cloudflare resolver and
		// persisted WebView cookie/UA handling can be applied without forcing
		// the Dart-only HTTP profile.
		this._httpClient = new Client();
	}

	get siteBase() {
		return String(this.source.baseUrl || "https://genzupdates.com").replace(
			/\/+$/,
			""
		);
	}

	getHeaders(_url) {
		return {
			Accept:
				"text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
			"Accept-Language": "en-US,en;q=0.9",
			"Cache-Control": "no-cache",
			Pragma: "no-cache",
			Referer: `${this.siteBase}/`
		};
	}

	_client() {
		return this._httpClient || new Client();
	}

	_isCloudflareChallengeHtml(html) {
		return /failed to bypass cloudflare|cf_chl|challenge-platform|Just a moment|Nur einen Moment|Security verification|Sicherheitsüberprüfung|Enable JavaScript and cookies|verify you are human|challenges\.cloudflare\.com|cf-turnstile|hcaptcha/i.test(
			String(html || "")
		);
	}

	_isCloudflareBlockedResponse(response) {
		const statusCode = Number(response?.statusCode || 0);
		const body = String(response?.body || "");
		if (statusCode === 403 || statusCode === 503) return true;
		return this._isCloudflareChallengeHtml(body);
	}

	_absoluteUrl(url) {
		const value = String(url || "").trim();
		if (!value) return "";
		if (/^https?:\/\//i.test(value)) return value;
		if (value.startsWith("//")) return `https:${value}`;
		if (value.startsWith("/")) return `${this.siteBase}${value}`;
		return `${this.siteBase}/${value}`;
	}

	_cleanText(text) {
		return String(text || "")
			.replace(/\u00a0/g, " ")
			.replace(/\s+/g, " ")
			.trim();
	}

	_decodeHtmlEntities(text) {
		return String(text || "")
			.replace(/&amp;/gi, "&")
			.replace(/&#38;/g, "&")
			.trim();
	}

	_stripHtml(html) {
		return this._cleanText(String(html || "").replace(/<[^>]+>/g, " "));
	}

	_extractUrlFromStyle(styleValue) {
		const style = String(styleValue || "");
		if (!style) return "";
		const match = style.match(/url\(([^)]+)\)/i);
		if (!match?.[1]) return "";
		return this._decodeHtmlEntities(
			this._cleanText(match[1]).replace(/^['"]|['"]$/g, "")
		);
	}

	_buildSeriesCoverMap(html) {
		const map = new Map();
		const source = String(html || "");
		const document = new Document(source);

		for (const link of document.select('a[href^="/series/"]')) {
			const path = this._normalizeSeriesPath(
				this._cleanText(link.attr("href"))
			);
			if (!path || map.has(path)) continue;
			const image =
				this._extractUrlFromStyle(link.attr("style")) ||
				this._extractUrlFromStyle(
					link.selectFirst('[style*="background-image"]')?.attr("style")
				);
			if (!path || !image || map.has(path)) continue;
			map.set(path, image);
		}

		if (map.size > 0) return map;

		for (const match of source.matchAll(
			/<a[^>]+href=(["'])(\/series\/[^"'?#]+\/?)\1[^>]*style=(["'])([\s\S]*?)\3[^>]*>/gi
		)) {
			const path = this._normalizeSeriesPath(match[2]);
			const image = this._extractUrlFromStyle(match[4]);
			if (!path || !image || map.has(path)) continue;
			map.set(path, image);
		}

		return map;
	}

	_throwIfChallenge(html, context) {
		if (this._isCloudflareChallengeHtml(html)) {
			throw new Error(
				`Cloudflare challenge blocked ${context}. Open Genz Updates in WebView and retry.`
			);
		}
	}

	_normalizeSeriesPath(url) {
		const raw = String(url || "").trim();
		if (!raw) return "";
		const cleaned = raw
			.replace(/^https?:\/\/[^/]+/i, "")
			.split("?")[0]
			.split("#")[0]
			.replace(/\/+$/, "");
		const match = cleaned.match(/\/series\/([^/?#]+)/i);
		if (!match) return "";
		return `/series/${match[1]}/`;
	}

	_normalizeChapterPath(url) {
		const raw = String(url || "").trim();
		if (!raw) return "";
		const cleaned = raw
			.replace(/^https?:\/\/[^/]+/i, "")
			.split("?")[0]
			.split("#")[0]
			.replace(/\/+$/, "");
		const match = cleaned.match(/\/chapter\/([^/?#]+)/i);
		if (!match) return "";
		return `/chapter/${match[1]}/`;
	}

	_parseDate(dateText) {
		const value = this._cleanText(dateText);
		if (!value) return null;
		const timestamp = Date.parse(value);
		if (Number.isNaN(timestamp)) return null;
		return String(timestamp);
	}

	_extractChapterNumber(chapterName) {
		const match = this._cleanText(chapterName).match(
			/Chapter\s*(\d+(?:\.\d+)?)/i
		);
		if (!match?.[1]) return null;
		const value = Number(match[1]);
		return Number.isFinite(value) ? value : null;
	}

	_parseRelativeDate(dateText) {
		const value = this._cleanText(dateText).toLowerCase();
		if (!value) return null;
		const now = Date.now();
		if (value === "today" || value === "just now") return String(now);
		if (value === "yesterday") return String(now - 24 * 60 * 60 * 1000);

		const match = value.match(
			/(\d+)\s*(second|minute|hour|day|week|month|year)s?\s*ago/
		);
		if (!match) return null;
		const amount = Number(match[1]);
		if (!Number.isFinite(amount) || amount <= 0) return null;

		const unitToMs = {
			second: 1000,
			minute: 60 * 1000,
			hour: 60 * 60 * 1000,
			day: 24 * 60 * 60 * 1000,
			week: 7 * 24 * 60 * 60 * 1000,
			month: 30 * 24 * 60 * 60 * 1000,
			year: 365 * 24 * 60 * 60 * 1000
		};
		const unit = match[2];
		const unitMs = unitToMs[unit];
		if (!unitMs) return null;
		return String(now - amount * unitMs);
	}

	_toStatus(statusText) {
		switch (String(statusText || "").toLowerCase()) {
			case "ongoing":
				return 0;
			case "completed":
				return 1;
			case "hiatus":
				return 2;
			case "dropped":
			case "cancelled":
			case "canceled":
				return 3;
			default:
				return 5;
		}
	}

	async _request(path) {
		const url = /^https?:\/\//i.test(path)
			? path
			: `${this.siteBase}${path.startsWith("/") ? "" : "/"}${path}`;
		const makeHeaders = (targetUrl, extra = {}) => ({
			...this.getHeaders(targetUrl),
			...extra
		});
		const client = this._client();
		let response = await client.get(url, makeHeaders(url));

		if (this._isCloudflareBlockedResponse(response)) {
			// Trigger Cloudflare/session warmups on multiple site routes.
			for (const warmupUrl of [
				`${this.siteBase}/`,
				`${this.siteBase}/series/`,
				`${this.siteBase}/latest/`
			]) {
				try {
					await client.get(warmupUrl, makeHeaders(warmupUrl));
				} catch (_err) {}
				response = await client.get(url, makeHeaders(url));
				if (!this._isCloudflareBlockedResponse(response)) break;
			}
		}

		if (this._isCloudflareBlockedResponse(response)) {
			throw new Error(
				`Cloudflare blocked request: ${url}. Open Genz Updates in WebView, refresh ${this.siteBase}/series/, then retry.`
			);
		}

		return response;
	}

	_collectSeriesFromHtml(html) {
		const document = new Document(html);
		const list = [];
		const seen = new Set();
		const coverBySeries = this._buildSeriesCoverMap(html);

		for (const link of document.select('a[href^="/series/"]')) {
			const hrefRaw = this._cleanText(link.attr("href"));
			const href = this._normalizeSeriesPath(hrefRaw);
			if (!href || seen.has(href)) continue;

			const titleNode = link.selectFirst("h3");
			const title = this._cleanText(
				titleNode ? titleNode.text : this._cleanText(link.text)
			);
			if (!title) continue;

			const img = link.selectFirst("img");
			const imageRaw =
				this._cleanText(img ? img.getSrc : "") ||
				this._cleanText(img ? img.attr("src") : "") ||
				this._cleanText(img ? img.getDataSrc : "") ||
				this._cleanText(img ? img.attr("data-src") : "") ||
				this._extractUrlFromStyle(link.attr("style")) ||
				this._extractUrlFromStyle(
					link.selectFirst('[style*="background-image"]')?.attr("style")
				) ||
				this._cleanText(coverBySeries.get(href) || "");

			list.push({
				name: title,
				imageUrl: this._absoluteUrl(this._decodeHtmlEntities(imageRaw)),
				link: href
			});
			seen.add(href);
		}

		if (list.length > 0) return list;

		for (const match of String(html).matchAll(
			/href="(\/series\/[^"?#]+\/?)"[\s\S]{0,600}?<h3[^>]*>([^<]+)<\/h3>/gi
		)) {
			const href = this._normalizeSeriesPath(match[1]);
			const name = this._cleanText(match[2]);
			if (!href || !name || seen.has(href)) continue;
			list.push({
				name,
				imageUrl: this._absoluteUrl(
					this._cleanText(coverBySeries.get(href) || "")
				),
				link: href
			});
			seen.add(href);
		}

		return list;
	}

	_hasNextPage(html, page, itemsLength) {
		const nextPage = page + 1;
		const document = new Document(html);
		const links = document.select(`a[href*="page=${nextPage}"]`);
		if (Array.isArray(links) && links.length > 0) return true;
		return itemsLength >= 20;
	}

	_getFilterValue(filters, index, fallback) {
		if (!Array.isArray(filters) || !filters[index]) return fallback;
		const filter = filters[index];
		if (!Array.isArray(filter.values)) return fallback;
		const selected = filter.values[filter.state];
		if (!selected || selected.value == null) return fallback;
		return String(selected.value);
	}

	async _seriesList(path, page) {
		const safePage = Number(page) > 0 ? Number(page) : 1;
		const separator = path.includes("?") ? "&" : "?";
		const res = await this._request(`${path}${separator}page=${safePage}`);
		this._throwIfChallenge(res.body, `series-list page ${safePage}`);
		const list = this._collectSeriesFromHtml(res.body);
		return {
			list,
			hasNextPage: this._hasNextPage(res.body, safePage, list.length)
		};
	}

	async getPopular(page) {
		return this._seriesList("/series/", page);
	}

	async getLatestUpdates(page) {
		return this._seriesList("/latest/", page);
	}

	getFilterList() {
		return [
			{
				type_name: "SelectFilter",
				name: "Type",
				state: 0,
				values: [
					{ type_name: "SelectOption", name: "All", value: "" },
					{ type_name: "SelectOption", name: "Manhwa", value: "manhwa" },
					{ type_name: "SelectOption", name: "Manga", value: "manga" },
					{ type_name: "SelectOption", name: "Manhua", value: "manhua" },
					{ type_name: "SelectOption", name: "Comic", value: "comic" },
					{
						type_name: "SelectOption",
						name: "Mangatoon",
						value: "mangatoon"
					}
				]
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
						value: "completed"
					},
					{ type_name: "SelectOption", name: "Hiatus", value: "hiatus" },
					{ type_name: "SelectOption", name: "Dropped", value: "dropped" }
				]
			},
			{
				type_name: "GroupFilter",
				name: "Genres",
				state: [
					{ type_name: "CheckBox", name: "Action", value: "action" },
					{ type_name: "CheckBox", name: "Adventure", value: "adventure" },
					{ type_name: "CheckBox", name: "Comedy", value: "comedy" },
					{ type_name: "CheckBox", name: "Drama", value: "drama" },
					{ type_name: "CheckBox", name: "Fantasy", value: "fantasy" },
					{ type_name: "CheckBox", name: "Romance", value: "romance" },
					{ type_name: "CheckBox", name: "Regression", value: "regression" },
					{ type_name: "CheckBox", name: "Delinquents", value: "delinquents" }
				]
			}
		];
	}

	async search(query, page, filters) {
		const safePage = Number(page) > 0 ? Number(page) : 1;
		const params = [];
		const pushParam = (key, value) => {
			if (value == null) return;
			const normalized = this._cleanText(String(value));
			if (!normalized) return;
			params.push(
				`${encodeURIComponent(key)}=${encodeURIComponent(normalized)}`
			);
		};
		pushParam("q", query);
		pushParam("page", safePage);

		const type = this._getFilterValue(filters, 0, "");
		const status = this._getFilterValue(filters, 1, "");
		pushParam("type", type);
		pushParam("status", status);

		const genreFilter = Array.isArray(filters) ? filters[2] : null;
		if (genreFilter && Array.isArray(genreFilter.state)) {
			const selected = genreFilter.state
				.filter((checkbox) => checkbox?.state)
				.map((checkbox) => String(checkbox.value || ""))
				.filter(Boolean);
			if (selected.length > 0) {
				pushParam("genre", selected[0]);
			}
		}

		const res = await this._request(`/series/?${params.join("&")}`);
		this._throwIfChallenge(res.body, `search page ${safePage}`);
		const list = this._collectSeriesFromHtml(res.body);
		return {
			list,
			hasNextPage: this._hasNextPage(res.body, safePage, list.length)
		};
	}

	_extractLongestParagraph(html) {
		let best = "";
		for (const match of String(html).matchAll(/<p[^>]*>([\s\S]*?)<\/p>/gi)) {
			const cleaned = this._stripHtml(match[1]);
			if (cleaned.length > best.length) best = cleaned;
		}
		return best;
	}

	_extractCover(html) {
		const ogImage = String(html).match(
			/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i
		);
		if (ogImage?.[1]) {
			return this._absoluteUrl(this._decodeHtmlEntities(ogImage[1]));
		}

		const wsrv = String(html).match(
			/https:\/\/wsrv\.nl\/\?url=cdn\.meowing\.org\/uploads\/[A-Za-z0-9._-]+(?:(?:&|&amp;)w=\d+)?/i
		);
		if (wsrv?.[0]) return this._absoluteUrl(this._decodeHtmlEntities(wsrv[0]));
		const cdn = String(html).match(
			/https:\/\/cdn\.meowing\.org\/uploads\/[A-Za-z0-9._-]+/i
		);
		if (cdn?.[0]) return this._absoluteUrl(cdn[0]);
		return "";
	}

	_extractMetaByLabel(text, label, nextLabels) {
		const escapedNext = nextLabels.map((item) =>
			item.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
		);
		const pattern = new RegExp(
			`${label}\\s+(.+?)\\s+(?:${escapedNext.join("|")})`,
			"i"
		);
		const match = text.match(pattern);
		return this._cleanText(match?.[1] || "");
	}

	_extractDetailMetaMap(html) {
		const meta = new Map();
		for (const match of String(html).matchAll(
			/<span>\s*(Author|Artist|Type|Status|Updated|Created)\s*<\/span>[\s\S]{0,300}?<div[^>]*>\s*([\s\S]{0,220}?)\s*<\/div>/gi
		)) {
			const key = this._cleanText(match[1]).toLowerCase();
			const value = this._stripHtml(this._decodeHtmlEntities(match[2]));
			if (!key || !value || meta.has(key)) continue;
			meta.set(key, value);
		}
		return meta;
	}

	async getDetail(url) {
		const seriesPath = this._normalizeSeriesPath(url);
		if (!seriesPath) {
			throw new Error(`Invalid series URL: ${url}`);
		}

		const res = await this._request(seriesPath);
		this._throwIfChallenge(res.body, `getDetail ${seriesPath}`);

		const html = res.body;
		const document = new Document(html);
		const bodyText = this._cleanText(document.body ? document.body.text : "");
		const detailMeta = this._extractDetailMetaMap(html);

		const genres = [];
		for (const tag of document.select('a[href*="/series/?genre="]')) {
			const name = this._cleanText(tag.text);
			if (!name) continue;
			if (!genres.includes(name)) genres.push(name);
		}

		const author =
			this._cleanText(detailMeta.get("author") || "") ||
			this._extractMetaByLabel(bodyText, "Author", [
				"Artist",
				"Type",
				"Status"
			]);
		const artist =
			this._cleanText(detailMeta.get("artist") || "") ||
			this._extractMetaByLabel(bodyText, "Artist", [
				"Type",
				"Status",
				"Updated"
			]);
		const statusText =
			this._cleanText(detailMeta.get("status") || "") ||
			this._extractMetaByLabel(bodyText, "Status", [
				"Updated",
				"Created",
				"Synopsis"
			]);

		const chapters = [];
		const seenChapters = new Set();
		for (const chapter of document.select('a[href^="/chapter/"]')) {
			const chapterPath = this._normalizeChapterPath(chapter.attr("href"));
			if (!chapterPath) continue;
			const chapterClass = this._cleanText(chapter.attr("class"));
			const chapterTitle = this._cleanText(chapter.attr("title"));
			const chapterAlt = this._cleanText(chapter.attr("alt"));
			const chapterNumber = this._cleanText(chapter.attr("c"));
			const chapterDate = this._cleanText(chapter.attr("d"));
			const isListingChapter = /\bgroup\b/i.test(chapterClass) || !!chapterDate;
			if (!isListingChapter || seenChapters.has(chapterPath)) continue;
			const rawText = this._cleanText(
				`${chapterTitle} ${chapterAlt} ${chapterDate} ${chapter.text}`
			);
			if (!rawText && !chapterPath) continue;

			const chapterNameMatch = rawText.match(
				/Chapter\s*\d+(?:\.\d+)?(?:\s*[-:–]\s*[^\n]+)?/i
			);
			let chapterName = this._cleanText(
				chapterNameMatch?.[0] || chapterTitle || chapterAlt
			);
			if (!chapterName && /^\d+(?:\.\d+)?$/.test(chapterNumber)) {
				chapterName = `Chapter ${chapterNumber}`;
			}
			if (!chapterName) {
				const chapterId = chapterPath
					.replace(/^\/chapter\//, "")
					.replace(/\/$/, "");
				chapterName = `Chapter ${chapterId}`;
			}

			if (/\bCoin\b/i.test(rawText) && !/\(Coin\)$/i.test(chapterName)) {
				chapterName = `${chapterName} (Coin)`;
			}

			const dateMatch = rawText.match(
				/\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{1,2},\s+\d{4}\b/i
			);
			const parsedDate =
				this._parseDate(dateMatch?.[0] || "") ||
				this._parseRelativeDate(chapterDate) ||
				this._parseRelativeDate(rawText);

			chapters.push({
				name: chapterName,
				url: chapterPath,
				dateUpload: parsedDate
			});
			seenChapters.add(chapterPath);
		}
		chapters.sort((a, b) => {
			const aNumber = this._extractChapterNumber(a.name);
			const bNumber = this._extractChapterNumber(b.name);
			if (aNumber != null && bNumber != null && aNumber !== bNumber) {
				return bNumber - aNumber;
			}
			const aDate = Number(a.dateUpload || 0);
			const bDate = Number(b.dateUpload || 0);
			if (aDate !== bDate) return bDate - aDate;
			return 0;
		});

		return {
			imageUrl: this._extractCover(html),
			description: this._extractLongestParagraph(html),
			genre: genres,
			author,
			artist,
			status: this._toStatus(statusText),
			chapters
		};
	}

	async getPageList(url) {
		const chapterPath = this._normalizeChapterPath(url);
		if (!chapterPath) throw new Error(`Invalid chapter URL: ${url}`);

		const res = await this._request(chapterPath);
		this._throwIfChallenge(res.body, `getPageList ${chapterPath}`);

		const html = res.body;
		if (
			/early access chapter|purchase the chapter|sign in and then purchase/i.test(
				html
			)
		) {
			return [];
		}

		const pages = [];
		const seen = new Set();
		const document = new Document(html);
		for (const img of document.select("img")) {
			let src =
				this._cleanText(img ? img.getSrc : "") ||
				this._cleanText(img ? img.attr("src") : "") ||
				this._cleanText(img ? img.getDataSrc : "") ||
				this._cleanText(img ? img.attr("data-src") : "");
			const uid = this._cleanText(img ? img.attr("uid") : "");
			if ((!src || /placeholder\.svg/i.test(src)) && uid) {
				src = `https://cdn.meowing.org/uploads/${uid}`;
			}
			if (!/cdn\.meowing\.org\/uploads\//i.test(src)) continue;
			const absolute = this._absoluteUrl(src);
			if (!absolute || seen.has(absolute)) continue;
			seen.add(absolute);
			pages.push(absolute);
		}

		if (pages.length > 0) return pages;

		for (const match of String(html).matchAll(
			/https:\/\/cdn\.meowing\.org\/uploads\/[A-Za-z0-9._-]+/gi
		)) {
			const page = this._cleanText(match[0]);
			if (!page || seen.has(page)) continue;
			seen.add(page);
			pages.push(page);
		}

		for (const uidMatch of String(html).matchAll(
			/\buid="([A-Za-z0-9._-]+)"/gi
		)) {
			const page = `https://cdn.meowing.org/uploads/${this._cleanText(uidMatch[1])}`;
			if (!/cdn\.meowing\.org\/uploads\//i.test(page) || seen.has(page))
				continue;
			seen.add(page);
			pages.push(page);
		}

		return pages;
	}
}
