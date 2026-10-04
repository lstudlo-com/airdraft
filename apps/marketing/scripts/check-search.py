#!/usr/bin/env python3
"""Check the shipped search contract, optionally against a local HTTP preview.

No network requests unless --base-url is supplied. Uses only Python's stdlib.
"""

import argparse
import json
import re
import struct
from html.parser import HTMLParser
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import unquote, urljoin, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
from urllib.robotparser import RobotFileParser
from xml.etree import ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"


class Page(HTMLParser):
    def __init__(self, source):
        super().__init__(convert_charrefs=True)
        self.meta = {}
        self.links = []
        self.anchors = []
        self.ids = set()
        self.h1_count = 0
        self.title = ""
        self.in_title = False
        self.in_schema = False
        self.schemas = []
        self.schema = ""
        self.language = None
        self.feed(source)

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if attrs.get("id"):
            self.ids.add(attrs["id"])
        if tag == "html":
            self.language = attrs.get("lang")
        if tag == "meta":
            self.meta[attrs.get("name", attrs.get("property"))] = attrs.get("content", "")
        if tag == "link":
            self.links.append(attrs)
        if tag == "a" and "href" in attrs:
            self.anchors.append(attrs["href"])
        if tag == "h1":
            self.h1_count += 1
        if tag == "title":
            self.in_title = True
        if tag == "script" and attrs.get("type") == "application/ld+json":
            self.in_schema = True
            self.schema = ""

    def handle_endtag(self, tag):
        if tag == "title":
            self.in_title = False
        if tag == "script" and self.in_schema:
            self.schemas.append(json.loads(self.schema))
            self.in_schema = False

    def handle_data(self, value):
        if self.in_title:
            self.title += value
        if self.in_schema:
            self.schema += value

    def hrefs(self, relation):
        return [link["href"] for link in self.links if link.get("rel") == relation]


def graph_nodes(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from graph_nodes(child)
    elif isinstance(value, list):
        for child in value:
            yield from graph_nodes(child)


def check(base_url=None):
    errors = []

    def require(condition, message):
        if not condition:
            errors.append(message)

    files = sorted(DIST.rglob("*.html"))
    require(bool(files), "No built HTML. Run astro build first.")
    pages = {}
    for path in files:
        relative = path.relative_to(DIST).as_posix()
        route = "/" + relative.removesuffix("index.html") if relative.endswith("index.html") else "/" + relative
        try:
            pages[route] = Page(path.read_text())
        except (ValueError, UnicodeError) as error:
            errors.append(f"{route}: invalid HTML/JSON-LD: {error}")
    if "/" not in pages:
        raise AssertionError("Built homepage missing.")
    home = pages["/"]
    origin = urlsplit(home.hrefs("canonical")[0])._replace(path="", query="", fragment="").geturl()
    require(origin.startswith("https://"), "Canonical origin must use HTTPS.")
    indexable = {route: page for route, page in pages.items() if "noindex" not in page.meta.get("robots", "")}
    require("/design/" in pages and "/design/" not in indexable, "Design reference must remain noindex.")
    require("/404.html" in pages and "/404.html" not in indexable, "404 must remain noindex.")
    require(not pages.get("/404.html", home).hrefs("canonical"), "404 must not canonicalize missing paths.")
    titles, descriptions = set(), set()
    adjacency = {}
    for route, page in pages.items():
        require(page.language == "en", f"{route}: missing English language.")
        require(page.h1_count == 1, f"{route}: expected one H1, got {page.h1_count}.")
        adjacency[route] = set()
        for href in page.anchors:
            link = urlsplit(urljoin(origin + route, href))
            if link.netloc != urlsplit(origin).netloc or link.scheme not in ("http", "https"):
                continue
            target = unquote(link.path)
            exists = target in pages or (DIST / target.lstrip("/")).is_file()
            require(exists, f"{route}: broken internal link {href}.")
            if target in pages:
                adjacency[route].add(target)
                if link.fragment:
                    require(unquote(link.fragment) in pages[target].ids, f"{route}: missing anchor {href}.")
        if route not in indexable:
            continue
        require(route.endswith("/"), f"{route}: HTML canonical routes must use trailing slashes.")
        require(page.hrefs("canonical") == [origin + route], f"{route}: canonical must match sitemap URL.")
        require(page.title.strip() and page.title not in titles, f"{route}: missing/duplicate title.")
        titles.add(page.title)
        description = page.meta.get("description", "")
        require(description.strip() and description not in descriptions, f"{route}: missing/duplicate description.")
        descriptions.add(description)
        require(page.meta.get("og:url") == origin + route, f"{route}: OG URL mismatch.")
        require(page.meta.get("og:title") == page.title, f"{route}: OG title mismatch.")
        require(page.meta.get("og:description") == description, f"{route}: OG description mismatch.")
        require(page.meta.get("og:site_name") == "Airdraft", f"{route}: missing site name.")
        require(page.meta.get("twitter:card") == "summary_large_image", f"{route}: missing large social preview.")
        require(page.meta.get("og:image:width") == "1200" and page.meta.get("og:image:height") == "630", f"{route}: social image dimensions.")
        require(page.meta.get("og:image:alt"), f"{route}: social image alt missing.")
        require(page.meta.get("og:image") == origin + "/social-card.png", f"{route}: social image URL mismatch.")
        robots = page.meta.get("robots", "")
        require("max-image-preview:large" in robots, f"{route}: large preview permission missing.")
        require(not re.search(r"nosnippet|noai|max-snippet:0", robots), f"{route}: unexpected snippet restriction.")
        require(any(link.get("type") == "application/rss+xml" and urljoin(origin, link.get("href", "")) == origin + "/changelog.xml" for link in page.links), f"{route}: RSS discovery missing.")
        nodes = [node for schema in page.schemas for node in graph_nodes(schema)]
        require(any(node.get("@type") == "WebPage" and node.get("url") == origin + route for node in nodes), f"{route}: WebPage structured data missing.")
        require(not any("aggregateRating" in node or "review" in node or "offers" in node for node in nodes), f"{route}: unsupported review or offer claim.")
    root_nodes = [node for schema in home.schemas for node in graph_nodes(schema)]
    require(any(node.get("@type") == "WebSite" and node.get("name") == "Airdraft" and node.get("url") == origin + "/" for node in root_nodes), "Homepage WebSite identity missing.")
    require(any(node.get("@type") == "SoftwareApplication" and node.get("name") == "Airdraft" for node in root_nodes), "Homepage software identity missing.")
    reachable, pending = set(), ["/"]
    while pending:
        route = pending.pop()
        if route not in reachable:
            reachable.add(route)
            pending.extend(adjacency.get(route, set()) - reachable)
    require(set(indexable) <= reachable, f"Orphan pages: {set(indexable) - reachable}")
    namespace = {"s": "http://www.sitemaps.org/schemas/sitemap/0.9"}
    sitemap_index = ET.parse(DIST / "sitemap-index.xml")
    sitemap_urls = []
    for loc in sitemap_index.findall("s:sitemap/s:loc", namespace):
        require(loc.text.startswith(origin + "/"), "Sitemap index origin mismatch.")
        sitemap = ET.parse(DIST / urlsplit(loc.text).path.lstrip("/"))
        sitemap_urls.extend(element.text for element in sitemap.findall("s:url/s:loc", namespace))
    require(set(sitemap_urls) == {origin + route for route in indexable}, "Sitemap must contain exactly the indexable canonical HTML pages.")
    require(len(sitemap_urls) == len(set(sitemap_urls)), "Duplicate sitemap URL.")
    redirects = {}
    for line in (DIST / "_redirects").read_text().splitlines():
        if line.strip() and not line.lstrip().startswith("#"):
            source, target, status = line.split()
            redirects[source] = (target, status)
    for route in indexable:
        require(redirects.get(route + "index.html") == (route, "301"), f"{route}: missing permanent index.html redirect.")
        if route != "/":
            require(redirects.get(route.rstrip("/")) == (route, "301"), f"{route}: missing permanent slashless redirect.")
    robots_text = (DIST / "robots.txt").read_text()
    robots_parser = RobotFileParser()
    robots_parser.parse(robots_text.splitlines())
    require(robots_parser.site_maps() == [origin + "/sitemap-index.xml"], "Robots sitemap mismatch.")
    for bot in ["Googlebot", "Bingbot", "OAI-SearchBot", "Claude-SearchBot", "PerplexityBot", "ChatGPT-User", "Claude-User", "Perplexity-User", "GPTBot", "ClaudeBot", "ExampleBot"]:
        for url in sitemap_urls:
            require(robots_parser.can_fetch(bot, url), f"{bot} blocked from {url}.")
    feed = ET.parse(DIST / "changelog.xml")
    items = feed.findall("channel/item")
    require(bool(items), "RSS has no entries.")
    guids = []
    for item in items:
        link = item.findtext("link", "")
        target = urlsplit(link)
        require(target.netloc == urlsplit(origin).netloc and target.path == "/changelog/" and target.fragment in pages["/changelog/"].ids, f"RSS entry target missing: {link}.")
        require(item.findtext("pubDate") and item.findtext("description"), f"RSS entry incomplete: {link}.")
        guids.append(item.findtext("guid"))
    require(len(guids) == len(set(guids)), "RSS GUIDs must be unique.")
    directory = (DIST / "llms.txt").read_text()
    for link in re.findall(r"\]\((https://[^)]+)\)", directory):
        target = urlsplit(link)
        if target.netloc == urlsplit(origin).netloc:
            require(target.path in indexable, f"llms.txt links to non-indexable page {link}.")
    image = (DIST / "social-card.png").read_bytes()
    require(image[:8] == b"\x89PNG\r\n\x1a\n" and struct.unpack(">II", image[16:24]) == (1200, 630), "Social preview must be a real 1200x630 PNG.")
    require(re.fullmatch(r"[A-Za-z0-9-]{8,128}", (DIST / "indexnow-key.txt").read_text().strip()), "Invalid IndexNow key.")
    if base_url:
        class NoRedirect(HTTPRedirectHandler):
            def redirect_request(self, *args, **kwargs):
                return None
        opener = build_opener(NoRedirect())
        def fetch(route):
            try:
                response = opener.open(Request(base_url.rstrip("/") + route), timeout=15)
            except HTTPError as error:
                response = error
            with response:
                return response.code, response.headers, response.read()
        for route in indexable:
            status, headers, body = fetch(route)
            require(status == 200 and "text/html" in headers.get("Content-Type", ""), f"HTTP {route}: expected HTML 200, got {status}.")
            require(not re.search(r"noindex|none|nosnippet|max-snippet:\s*0", headers.get("X-Robots-Tag", ""), re.I), f"HTTP {route}: restrictive X-Robots-Tag.")
            require(Page(body.decode()).hrefs("canonical") == [origin + route], f"HTTP {route}: canonical changed.")
            require(body == (DIST / route.lstrip("/") / "index.html").read_bytes(), f"HTTP {route}: served HTML differs from the checked build.")
            if route != "/":
                status, headers, _ = fetch(route.rstrip("/"))
                require(status in (301, 308) and urlsplit(headers.get("Location", "")).path == route, f"HTTP {route}: trailing slash redirect missing.")
            status, headers, _ = fetch(route + "index.html")
            require(status in (301, 308) and urlsplit(headers.get("Location", "")).path == route, f"HTTP {route}: index.html redirect missing.")
        discovery_assets = [("/robots.txt", "text/plain"), ("/llms.txt", "text/plain"), ("/changelog.xml", "application/rss+xml"), ("/sitemap-index.xml", "application/xml"), ("/indexnow-key.txt", "text/plain"), ("/social-card.png", "image/png")]
        discovery_assets.extend((urlsplit(loc.text).path, "application/xml") for loc in sitemap_index.findall("s:sitemap/s:loc", namespace))
        for route, mime in discovery_assets:
            status, headers, body = fetch(route)
            require(status == 200 and mime in headers.get("Content-Type", ""), f"HTTP {route}: expected {mime} 200, got {status} {headers.get('Content-Type')}.")
            require(body == (DIST / route.lstrip("/")).read_bytes(), f"HTTP {route}: served discovery asset differs from the checked build.")
        status, _, body = fetch("/__search-check-missing__/")
        require(status == 404 and "noindex" in Page(body.decode()).meta.get("robots", ""), "Missing path must return HTTP 404 with noindex.")
    if errors:
        raise AssertionError("\n".join(errors))
    print(f"Search checks passed: {len(indexable)} indexable pages, canonical/sitemap parity, crawlable internal links, AI/search permissions, structured data, {len(items)} feed entries, social image" + (", HTTP routes." if base_url else "."))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", help="Optional local preview origin for HTTP status and MIME checks")
    args = parser.parse_args()
    check(args.base_url)
