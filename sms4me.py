#!/usr/bin/env python3
import argparse
import random
import re
import sys
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import urljoin

from bs4 import BeautifulSoup

try:
    from curl_cffi import requests as http
    KW = {"impersonate": "chrome"}
except ImportError:
    import requests as http
    KW = {}

HDR = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
}
R, G, Y, C, D, B, X = "\033[91m", "\033[92m", "\033[93m", "\033[96m", "\033[2m", "\033[1m", "\033[0m"

ALIASES = {
    "uk": "united kingdom", "gb": "united kingdom", "us": "united states", "usa": "united states",
    "fr": "france", "de": "germany", "nl": "netherlands", "be": "belgium", "ch": "switzerland",
    "es": "spain", "it": "italy", "pl": "poland", "se": "sweden", "fi": "finland", "ca": "canada",
    "pt": "portugal", "ro": "romania", "dk": "denmark", "no": "norway", "at": "austria",
    "ie": "ireland", "au": "australia", "in": "india", "br": "brazil", "mx": "mexico",
    "cz": "czech", "ee": "estonia", "lt": "lithuania", "lv": "latvia", "hr": "croatia",
    "hk": "hong kong", "cn": "china", "si": "slovenia", "vn": "vietnam", "ua": "ukraine",
    "ru": "russia", "il": "israel", "id": "indonesia", "ph": "philippines", "my": "malaysia",
    "th": "thailand", "ma": "morocco", "za": "south africa", "jp": "japan", "kr": "korea",
}
CODES = {
    "1": ["united states", "canada", "puerto rico"], "7": ["russia", "kazakhstan"], "20": ["egypt"],
    "27": ["south africa"], "30": ["greece"], "31": ["netherlands"], "32": ["belgium"], "33": ["france"],
    "34": ["spain"], "36": ["hungary"], "39": ["italy"], "40": ["romania"], "41": ["switzerland"],
    "43": ["austria"], "44": ["united kingdom"], "45": ["denmark"], "46": ["sweden"], "47": ["norway"],
    "48": ["poland"], "49": ["germany"], "52": ["mexico"], "55": ["brazil"], "60": ["malaysia"],
    "61": ["australia"], "62": ["indonesia"], "63": ["philippines"], "66": ["thailand"], "81": ["japan"],
    "82": ["korea"], "84": ["vietnam"], "86": ["china"], "90": ["turkey", "türkiye"], "91": ["india"],
    "212": ["morocco"], "234": ["nigeria"], "351": ["portugal"], "353": ["ireland"], "358": ["finland"],
    "359": ["bulgaria"], "370": ["lithuania"], "371": ["latvia"], "372": ["estonia"], "380": ["ukraine"],
    "381": ["serbia"], "385": ["croatia"], "386": ["slovenia"], "420": ["czech"], "852": ["hong kong"],
    "853": ["macao", "macau"], "855": ["cambodia"], "886": ["taiwan"], "972": ["israel"],
}
AGO = re.compile(r"(\d+)\s+(second|minute|hour|day|week|month|year)s?\s+ago", re.I)
UNIT = {"second": 1, "minute": 60, "hour": 3600, "day": 86400, "week": 604800, "month": 2592000, "year": 31536000}
NOISE = re.compile(r"^(\d+\s+(second|minute|hour|day|week|month|year)s?\s+ago|just now|advertisement|refresh|.|\d+\s+today.*)$", re.I)

_tls = threading.local()
PROXY = {}


def fetch(url):
    s = getattr(_tls, "s", None)
    if s is None:
        s = _tls.s = http.Session()
    sep = "&" if "?" in url else "?"
    r = s.get(f"{url}{sep}cb={uuid.uuid4().hex}", headers=HDR, timeout=20, proxies=PROXY or None, **KW)
    r.raise_for_status()
    return r


def get(url):
    return BeautifulSoup(fetch(url).text, "html.parser")


def get_json(url):
    return fetch(url).json()


def generic_inbox(soup, counter_re=None):
    out = []
    for tr in soup.select("table tr"):
        cells = [txt(td) for td in tr.find_all("td")]
        cells = [c for c in cells if c and not AGO.fullmatch(c) and not NOISE.match(c)]
        if len(cells) >= 2:
            out.append(" : ".join(cells))
    if not out:
        lines = [l.strip() for l in soup.get_text("\n").split("\n") if l.strip()]
        out = [l for l in lines if not NOISE.match(l) and not AGO.search(l)]
    count = None
    if counter_re:
        m = re.search(counter_re, soup.get_text(" "), re.I)
        count = int(m.group(1).replace(",", "")) if m else None
    return count, out


def digits(s):
    return re.sub(r"\D", "", s or "")


def txt(node):
    return re.sub(r"\s+", " ", node.get_text(" ", strip=True)) if node else ""


def age(text):
    m = AGO.search(text or "")
    return int(m.group(1)) * UNIT[m.group(2).lower()] if m else 10 ** 10


def human(sec):
    if not sec:
        return "-"
    if sec >= 10 ** 10:
        return "?"
    for u, v in (("y", 31536000), ("mo", 2592000), ("d", 86400), ("h", 3600), ("m", 60)):
        if sec >= v:
            return f"{sec // v}{u}"
    return f"{sec}s"


def parse_query(q):
    if not q:
        return None, None
    q = q.strip()
    if re.fullmatch(r"(\+|00)?\d{1,4}", q):
        return "code", re.sub(r"^(\+|00)", "", q)
    return "name", ALIASES.get(q.lower(), q.lower())


def code_names(val):
    return [n for k, v in CODES.items() if val.startswith(k) or k.startswith(val) for n in v]


class Provider:
    name = ""
    block = 1

    def index(self):
        raise NotImplementedError

    def numbers(self, c):
        raise NotImplementedError

    def entry(self, num, country, url, a=0):
        return {"p": self, "num": num, "country": country, "url": url, "age": a}

    def safe_numbers(self, c):
        try:
            return self.numbers(c)
        except Exception:
            return []

    def select(self, idx, kind, val):
        if kind == "name":
            return [c for c in idx if val in c["name"].lower() or val.replace(" ", "-") in c.get("slug", "")]
        if kind == "code":
            if any(c.get("code") for c in idx):
                return [c for c in idx if c.get("code") and (c["code"].startswith(val) or val.startswith(c["code"]))]
            names = code_names(val)
            sel = [c for c in idx if any(n in c["name"].lower() for n in names)]
            return sel or idx
        return random.sample(idx, min(3, len(idx)))

    def find(self, kind, val):
        sel = self.select(self.index(), kind, val)
        with ThreadPoolExecutor(8) as ex:
            res = [e for lst in ex.map(self.safe_numbers, sel) for e in lst]
        return [e for e in res if e["num"].startswith(val)] if kind == "code" else res

    def countries(self):
        return [(c["name"], f"+{c['code']}" if c.get("code") else "", c.get("count", ""))
                for c in sorted(self.index(), key=lambda c: c["name"].lower())]


class CatalogProvider(Provider):
    def catalog(self):
        raise NotImplementedError

    def find(self, kind, val):
        cat = self.catalog()
        if kind == "code":
            return [e for e in cat if e["num"].startswith(val)]
        if kind == "name":
            return [e for e in cat if val in e["country"].lower()]
        return cat

    def countries(self):
        out = {}
        for e in self.catalog():
            out[e["country"]] = out.get(e["country"], 0) + 1
        return [(c, "", n) for c, n in sorted(out.items())]


class ReceiveSmss(CatalogProvider):
    name = "receive-smss"
    base = "https://receive-smss.com"

    def catalog(self):
        soup = get(f"{self.base}/")
        out = []
        nbr = [txt(n) for n in soup.select(".number-boxes-itemm-number")]
        if nbr:
            loc = [txt(n) for n in soup.select(".number-boxes-item-country")]
            btn = [txt(n) for n in soup.select(".number-boxes1-item-button")]
            btn += ["Open"] * (len(nbr) - len(btn))
            out = [self.entry(digits(n), l, f"{self.base}/sms/{digits(n)}/")
                   for n, l, s in zip(nbr, loc, btn) if s.lower() == "open"]
        if not out:
            for a in soup.select("div.number-boxes-item > a"):
                n = digits(txt(a.select_one("div")))
                if n:
                    out.append(self.entry(n, txt(a.select_one(".number-boxes-item-country")),
                                          urljoin(self.base, a.get("href", f"/sms/{n}/"))))
        if not out:
            raise RuntimeError("aucun numéro parsé (structure changée ou Cloudflare)")
        return out

    def inbox(self, e):
        soup = get(e["url"])
        out = []
        for row in soup.select(".message_details"):
            s = row.select_one(".senderr a, .senderr")
            m = row.select_one(".msgg span") or row.select_one("label + br + span") or row.select_one(".msgg")
            out.append(f"{txt(s) or '?'} : {txt(m)}")
        if not out:
            cells = [txt(c) for c in soup.select(".wr3pc333el1878")]
            out = [f"{cells[i]} : {cells[i + 1]}" for i in range(0, len(cells) - 2, 3)]
        return None, out


class TempNumber(Provider):
    name = "temp-number"
    base = "https://temp-number.com"
    block = 2

    def index(self):
        soup = get(f"{self.base}/countries")
        seen, out = set(), []
        for a in soup.select('a[href*="/countries/"]'):
            slug = a.get("href", "").rstrip("/").split("/countries/")[-1]
            if not slug or "/" in slug or slug in seen:
                continue
            t = txt(a)
            m = re.search(r"\+?(\d{1,4})\s+(\d+)\s+numbers?\b", t)
            if not m or int(m.group(2)) == 0:
                continue
            seen.add(slug)
            out.append({"slug": slug, "name": t[:m.start()].replace("Trending", "").strip(),
                        "code": m.group(1), "count": int(m.group(2))})
        if not out:
            raise RuntimeError("index pays vide (structure changée ou Cloudflare)")
        return out

    def numbers(self, c):
        soup = get(f"{self.base}/countries/{c['slug']}")
        out, seen = [], set()
        for a in soup.select(f'a[href*="/temporary-numbers/{c["slug"]}/"]'):
            m = re.search(r"/temporary-numbers/[^/]+/(\d+)", a.get("href", ""))
            if not m or m.group(1) in seen:
                continue
            seen.add(m.group(1))
            out.append(self.entry(m.group(1), c["name"], f"{self.base}/temporary-numbers/{c['slug']}/{m.group(1)}",
                                  age(a.find_previous(string=AGO))))
        return out

    def inbox(self, e):
        text = get(e["url"]).get_text("\n")
        lines = [l.strip() for l in text.split("\n") if l.strip()]
        start = next((i for i, l in enumerate(lines) if "total messages received" in l.lower()), None)
        if start is None:
            start = next((i for i, l in enumerate(lines) if l.lower() == "sms messages"), 0)
        end = next((i for i in range(start + 1, len(lines)) if re.match(r"^Page \d+ of \d+", lines[i])), len(lines))
        msgs = [l for l in lines[start + 1:end] if not NOISE.match(l)]
        m = re.search(r"([\d,]+)\s+total messages received", text, re.I)
        return (int(m.group(1).replace(",", "")) if m else None), msgs


class Sms24(Provider):
    name = "sms24.me"
    base = "https://sms24.me"

    def index(self):
        soup = get(f"{self.base}/en/countries")
        out, seen = [], set()
        for a in soup.select("div.container a.callout"):
            href = a.get("href", "")
            if not href or href in seen:
                continue
            seen.add(href)
            out.append({"name": txt(a), "url": urljoin(self.base, href), "slug": href.rstrip("/").split("/")[-1]})
        if not out:
            raise RuntimeError("index pays vide (structure changée ou Cloudflare)")
        return out

    def numbers(self, c):
        soup = get(c["url"])
        out = []
        for a in soup.select("div.col-sm-12 > a.callout.m-2"):
            n = digits(txt(a.select_one("div.text-primary")) or a.get("href", "").split("/")[-1])
            if n:
                out.append(self.entry(n, c["name"], urljoin(self.base, a.get("href", f"/en/numbers/{n}"))))
        return out

    def inbox(self, e):
        soup = get(f"{e['url'].rstrip('/')}/1")
        out = []
        for dd in soup.select("dl dd"):
            s = txt(dd.select_one("a")).replace("From:", "").strip()
            out.append(f"{s or '?'} : {txt(dd.select_one('span'))}")
        return None, out


class FreePhoneNum(Provider):
    name = "freephonenum"
    base = "https://freephonenum.com"

    def index(self):
        soup = get(f"{self.base}/")
        out, seen = [], set()
        for sp in soup.select("div.container div.row a > span:nth-child(1)"):
            a = sp.parent
            href = urljoin(self.base + "/", a.get("href", ""))
            if href in seen:
                continue
            seen.add(href)
            parts = txt(sp).split(" ")
            cnt = parts[-1] if parts and parts[-1].isdigit() else ""
            name = " ".join(parts[:-1] if cnt else parts)
            if cnt == "0":
                continue
            out.append({"name": name, "url": href, "count": cnt, "slug": href.rstrip("/").split("/")[-1]})
        if not out:
            raise RuntimeError("index pays vide (structure changée ou Cloudflare)")
        return out

    def numbers(self, c):
        soup = get(c["url"])
        out = []
        for a in soup.select("div.container a.numbers-btn:not(.disabled)"):
            n = digits(txt(a.select_one("div")))
            if n:
                out.append(self.entry(n, c["name"], urljoin(self.base + "/", a.get("href", ""))))
        return out

    def inbox(self, e):
        soup = get(e["url"])
        out = []
        for tr in soup.select("tbody tr"):
            m = tr.select_one("td:nth-child(3)")
            if m:
                out.append(f"{txt(tr.select_one('td:nth-child(2)')) or '?'} : {txt(m)}")
        return None, out


class ReceiveSmsOnlineInfo(CatalogProvider):
    name = "receive-sms-online.info"
    base = "https://receive-sms-online.info"

    def catalog(self):
        soup = get(f"{self.base}/")
        out, seen = [], set()
        for a in soup.find_all("a", href=True):
            m = re.search(r"/(\d{8,15})-([A-Za-z][\w-]*)/?$", a["href"])
            if not m or m.group(1) in seen:
                continue
            box = a.find_parent(["div", "li", "tr"]) or a.parent
            if re.search(r"\b(offline|busy|disabled)\b", txt(box), re.I):
                continue
            seen.add(m.group(1))
            out.append(self.entry(m.group(1), m.group(2).replace("-", " "), urljoin(self.base + "/", a["href"])))
        if not out:
            raise RuntimeError("aucun numéro parsé (structure changée ou Cloudflare)")
        return out

    def inbox(self, e):
        return generic_inbox(get(e["url"]), r"Messages:\s*([\d,]+)")


class ReceiveFreeSmsNet(CatalogProvider):
    name = "receivefreesms.net"
    base = "https://receivefreesms.net"
    TAGS = {"CA": "canada", "UK": "united kingdom", "GB": "united kingdom", "USA": "united states", "US": "united states",
            "FR": "france", "DE": "germany", "SE": "sweden", "IN": "india", "UA": "ukraine", "PL": "poland", "JP": "japan"}

    def catalog(self):
        soup = get(f"{self.base}/")
        out, seen = [], set()
        for a in soup.find_all("a", href=True):
            ctx = txt(a.find_parent(["div", "li", "tr", "p"]) or a.parent)
            m = re.search(r"\+(\d{8,15})", ctx) or re.search(r"(\d{8,15})", a["href"])
            if not m or m.group(1) in seen:
                continue
            if "read" not in txt(a).lower() and m.group(1) not in a["href"]:
                continue
            seen.add(m.group(1))
            t = re.search(r"\b([A-Z]{2,3})\s*\+\d", ctx)
            tag = t.group(1) if t else "?"
            out.append(self.entry(m.group(1), self.TAGS.get(tag, tag).title(), urljoin(self.base + "/", a["href"])))
        if not out:
            raise RuntimeError("aucun numéro parsé (structure changée ou Cloudflare)")
        return out

    def inbox(self, e):
        return generic_inbox(get(e["url"]), r"Received\s+([\d,]+)\s+messages")


class OnlineSim(Provider):
    name = "onlinesim"
    base = "https://onlinesim.io"
    api = "https://onlinesim.io/api/getFreeList"

    def call(self, **params):
        q = "&".join(f"{k}={v}" for k, v in {"lang": "en", **params}.items())
        key = __import__("os").environ.get("ONLINESIM_KEY")
        if key:
            q += f"&apikey={key}"
        js = get_json(f"{self.api}?{q}")
        if js.get("response") not in (1, "1"):
            raise RuntimeError(f"API : {js.get('response')}")
        return js

    def index(self):
        out = []
        for c in self.call().get("countries", []):
            out.append({"name": c.get("country_text") or c.get("country_original", "?"),
                        "slug": c.get("country_original", ""), "code": str(c.get("country", ""))})
        if not out:
            raise RuntimeError("aucun pays gratuit")
        return out

    def numbers(self, c):
        nums = self.call(country=c["code"]).get("numbers") or {}
        items = nums.items() if isinstance(nums, dict) else ((n.get("number", ""), n) for n in nums)
        out = []
        for local, n in items:
            full = digits(n.get("full_number")) or f"{c['code']}{digits(str(local))}"
            if n.get("is_archive") or not full:
                continue
            e = self.entry(full, c["name"], f"{self.base}/free_numbers/{c['slug']}", age(n.get("data_humans")))
            e["local"], e["cc"] = digits(str(local)) or full[len(c["code"]):], c["code"]
            out.append(e)
        return out

    def inbox(self, e):
        if "local" not in e:
            raise RuntimeError("utilise la recherche par pays pour onlinesim (-n non supporté)")
        m = self.call(country=e["cc"], number=e["local"]).get("messages") or {}
        data = m.get("data", []) if isinstance(m, dict) else []
        return m.get("total") if isinstance(m, dict) else None, [f"{d.get('in_number', '?')} : {d.get('text', '')}" for d in data]


PROVIDERS = {
    "rs": ReceiveSmss(), "tn": TempNumber(), "s24": Sms24(), "fpn": FreePhoneNum(),
    "rsoi": ReceiveSmsOnlineInfo(), "rfs": ReceiveFreeSmsNet(), "os": OnlineSim(),
}
HOSTS = {"receive-smss.com": "rs", "temp-number.com": "tn", "sms24.me": "s24", "freephonenum.com": "fpn",
         "receive-sms-online.info": "rsoi", "receivefreesms.net": "rfs"}


def otp_of(lines):
    best = max(lines, key=len) if lines else ""
    cands = re.findall(r"(?<!\d)\d{4,8}(?!\d)", best)
    return sorted(cands, key=lambda c: len(c) != 6)[0] if cands else None


def gather(provs, fn):
    def run(p):
        try:
            return p, fn(p), None
        except Exception as ex:
            return p, [], ex
    with ThreadPoolExecutor(len(provs)) as ex:
        res = list(ex.map(run, provs))
    for p, _, err in res:
        if err:
            print(f"{R}[!] {p.name} : {type(err).__name__} {err}{X}")
    return res


def from_number(arg):
    host = next((h for h in HOSTS if h in arg), None)
    if host:
        p = PROVIDERS[HOSTS[host]]
        n = digits(re.search(r"(\d{6,})", arg).group(1)) if re.search(r"\d{6,}", arg) else "?"
        return p.entry(n, "?", arg)
    n = digits(arg)
    return PROVIDERS["rs"].entry(n, "?", f"{ReceiveSmss.base}/sms/{n}/")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("country", nargs="?", help="nom (uk, france...) ou indicatif (+86, 44...)")
    ap.add_argument("-p", "--provider", default="all", help=f"all ou liste : {','.join(PROVIDERS)}")
    ap.add_argument("-k", "--keyword", help="regex sur expéditeur/message (ex: nom de la cible)")
    ap.add_argument("-n", "--number", help="numéro receive-smss ou URL d'inbox d'un des sites")
    ap.add_argument("-i", "--interval", type=int, default=5)
    ap.add_argument("-t", "--timeout", type=int, default=600)
    ap.add_argument("-l", "--list", action="store_true")
    ap.add_argument("-x", "--proxy", help="ex: socks5h://127.0.0.1:9050")
    a = ap.parse_args()
    if a.proxy:
        PROXY.update({"http": a.proxy, "https": a.proxy})

    keys = list(PROVIDERS) if a.provider == "all" else [k.strip() for k in a.provider.split(",")]
    bad = [k for k in keys if k not in PROVIDERS]
    if bad:
        sys.exit(f"{R}[-] Provider inconnu : {','.join(bad)}{X} {D}({','.join(PROVIDERS)}){X}")
    provs = [PROVIDERS[k] for k in keys]

    if a.list:
        for p, rows, _ in gather(provs, lambda p: p.countries()):
            if rows:
                print(f"{B}{p.name}{X}")
                for name, code, n in rows:
                    print(f"  {C}{name:<28}{X}{code:<7}{n}")
        return

    if a.number:
        e = from_number(a.number)
    else:
        kind, val = parse_query(a.country)
        pool = [x for _, lst, _ in gather(provs, lambda p: p.find(kind, val)) for x in lst]
        if not pool:
            sys.exit(f"{R}[-] Aucun numéro pour '{a.country}'{X} {D}(essaie -l){X}")
        pool.sort(key=lambda x: x["age"])
        e = random.choice(pool[:5])
        per = {}
        for x in pool:
            per[x["p"].name] = per.get(x["p"].name, 0) + 1
        print(f"{D}[i] {len(pool)} numéro(s) : {', '.join(f'{k} {v}' for k, v in per.items())}{X}")

    p = e["p"]
    print(f"{G}[+]{X} {e['country']} : {B}{Y}+{e['num']}{X} {D}({p.name}, activité {human(e['age'])}){X}")
    print(f"{D}    {e['url']}{X}")

    last, msgs = p.inbox(e)
    seen = set(msgs)
    kw = re.compile(a.keyword, re.I) if a.keyword else None
    start = time.time()

    while time.time() - start < a.timeout:
        time.sleep(a.interval)
        el = int(time.time() - start)
        try:
            count, msgs = p.inbox(e)
        except Exception as ex:
            print(f"\r{R}[!] {type(ex).__name__}{X} {D}{el}s{X}   ", end="", flush=True)
            continue
        new = [m for m in msgs if m not in seen]
        seen.update(msgs)
        if not new and count is not None and last is not None and count > last:
            new = msgs[:p.block]
        if count is not None:
            last = count
        if new and (not kw or kw.search(" ".join(new))):
            print(f"\r{G}[SMS]{X} {' | '.join(new)}")
            otp = otp_of(new)
            if otp:
                print(f"{G}[OTP]{X} {B}{Y}{otp}{X}")
            sys.exit(0)
        print(f"\r{D}[~] écoute +{e['num']} ... {el}s{X}   ", end="", flush=True)

    print(f"\r{R}[-] Timeout {a.timeout}s, rien reçu{X}")
    sys.exit(1)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\r{R}[-] Stop{X}")
        sys.exit(130)