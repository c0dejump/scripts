#!/usr/bin/env python3
"""
fakidity.py  —  Fake Identity Generator
Usage:
    python fakidity.py <country> [--count N]
    python fakidity.py fr
    python fakidity.py france
    python fakidity.py french --count 3
"""

import argparse
import random
import sys
from datetime import date

from faker import Faker
from rich.console import Console
from rich.table import Table

console = Console(highlight=False)

# ── Locale registry ────────────────────────────────────────────────────────────
LOCALES: dict[str, tuple[str, str]] = {
    "fr_FR": ("France",          "🇫🇷"),
    "it_IT": ("Italy",           "🇮🇹"),
    "es_ES": ("Spain",           "🇪🇸"),
    "de_DE": ("Germany",         "🇩🇪"),
    "en_GB": ("United Kingdom",  "🇬🇧"),
    "en_US": ("United States",   "🇺🇸"),
    "en_CA": ("Canada",          "🇨🇦"),
    "fr_BE": ("Belgium",         "🇧🇪"),
    "fr_CH": ("Switzerland",     "🇨🇭"),
    "pt_PT": ("Portugal",        "🇵🇹"),
    "pt_BR": ("Brazil",          "🇧🇷"),
    "ja_JP": ("Japan",           "🇯🇵"),
    "zh_CN": ("China",           "🇨🇳"),
    "ru_RU": ("Russia",          "🇷🇺"),
    "pl_PL": ("Poland",          "🇵🇱"),
    "nl_NL": ("Netherlands",     "🇳🇱"),
    "tr_TR": ("Turkey",          "🇹🇷"),
    "es_MX": ("Mexico",          "🇲🇽"),
    "hi_IN": ("India",           "🇮🇳"),
    "ko_KR": ("South Korea",     "🇰🇷"),
    "sv_SE": ("Sweden",          "🇸🇪"),
    "da_DK": ("Denmark",         "🇩🇰"),
    "no_NO": ("Norway",          "🇳🇴"),
    "fi_FI": ("Finland",         "🇫🇮"),
    "uk_UA": ("Ukraine",         "🇺🇦"),
    "en_AU": ("Australia",       "🇦🇺"),
    "en_NZ": ("New Zealand",     "🇳🇿"),
    "es_AR": ("Argentina",       "🇦🇷"),
    "el_GR": ("Greece",          "🇬🇷"),
    "sk_SK": ("Slovakia",        "🇸🇰"),
    "sl_SI": ("Slovenia",        "🇸🇮"),
    "hr_HR": ("Croatia",         "🇭🇷"),
    "hu_HU": ("Hungary",         "🇭🇺"),
    "ro_RO": ("Romania",         "🇷🇴"),
    "bg_BG": ("Bulgaria",        "🇧🇬"),
    "cs_CZ": ("Czech Republic",  "🇨🇿"),
    "et_EE": ("Estonia",         "🇪🇪"),
    "lv_LV": ("Latvia",          "🇱🇻"),
    "lt_LT": ("Lithuania",       "🇱🇹"),
}

ALIASES: dict[str, str] = {
    "fr": "fr_FR", "france": "fr_FR", "french": "fr_FR", "fr_fr": "fr_FR",
    "it": "it_IT", "italy": "it_IT", "italian": "it_IT", "italie": "it_IT", "it_it": "it_IT",
    "es": "es_ES", "spain": "es_ES", "spanish": "es_ES", "espagne": "es_ES",
    "espana": "es_ES", "es_es": "es_ES",
    "de": "de_DE", "germany": "de_DE", "german": "de_DE", "allemagne": "de_DE",
    "deutschland": "de_DE", "de_de": "de_DE",
    "gb": "en_GB", "uk": "en_GB", "england": "en_GB", "britain": "en_GB",
    "great britain": "en_GB", "united kingdom": "en_GB", "british": "en_GB",
    "royaume-uni": "en_GB", "en_gb": "en_GB",
    "us": "en_US", "usa": "en_US", "america": "en_US", "american": "en_US",
    "united states": "en_US", "etats-unis": "en_US", "en_us": "en_US",
    "ca": "en_CA", "canada": "en_CA", "canadian": "en_CA", "en_ca": "en_CA",
    "be": "fr_BE", "belgium": "fr_BE", "belgian": "fr_BE", "belgique": "fr_BE",
    "ch": "fr_CH", "switzerland": "fr_CH", "swiss": "fr_CH", "suisse": "fr_CH",
    "pt": "pt_PT", "portugal": "pt_PT", "portuguese": "pt_PT", "pt_pt": "pt_PT",
    "br": "pt_BR", "brazil": "pt_BR", "brasil": "pt_BR", "bresil": "pt_BR", "pt_br": "pt_BR",
    "jp": "ja_JP", "japan": "ja_JP", "japanese": "ja_JP", "japon": "ja_JP", "ja_jp": "ja_JP",
    "cn": "zh_CN", "china": "zh_CN", "chinese": "zh_CN", "chine": "zh_CN", "zh_cn": "zh_CN",
    "ru": "ru_RU", "russia": "ru_RU", "russian": "ru_RU", "russie": "ru_RU", "ru_ru": "ru_RU",
    "pl": "pl_PL", "poland": "pl_PL", "polish": "pl_PL", "pologne": "pl_PL", "pl_pl": "pl_PL",
    "nl": "nl_NL", "netherlands": "nl_NL", "dutch": "nl_NL", "holland": "nl_NL",
    "pays-bas": "nl_NL", "nl_nl": "nl_NL",
    "tr": "tr_TR", "turkey": "tr_TR", "turkish": "tr_TR", "turquie": "tr_TR", "tr_tr": "tr_TR",
    "mx": "es_MX", "mexico": "es_MX", "mexican": "es_MX", "mexique": "es_MX",
    "in": "hi_IN", "india": "hi_IN", "indian": "hi_IN", "inde": "hi_IN",
    "kr": "ko_KR", "korea": "ko_KR", "south korea": "ko_KR", "korean": "ko_KR",
    "coree": "ko_KR", "ko_kr": "ko_KR",
    "se": "sv_SE", "sweden": "sv_SE", "swedish": "sv_SE", "suede": "sv_SE",
    "dk": "da_DK", "denmark": "da_DK", "danish": "da_DK", "danemark": "da_DK",
    "no": "no_NO", "norway": "no_NO", "norwegian": "no_NO", "norvege": "no_NO",
    "fi": "fi_FI", "finland": "fi_FI", "finnish": "fi_FI", "finlande": "fi_FI",
    "ua": "uk_UA", "ukraine": "uk_UA", "ukrainian": "uk_UA",
    "au": "en_AU", "australia": "en_AU", "australian": "en_AU", "australie": "en_AU",
    "nz": "en_NZ", "new zealand": "en_NZ", "kiwi": "en_NZ", "nouvelle-zelande": "en_NZ",
    "ar": "es_AR", "argentina": "es_AR", "argentine": "es_AR",
    "gr": "el_GR", "greece": "el_GR", "greek": "el_GR", "grece": "el_GR",
    "sk": "sk_SK", "slovakia": "sk_SK", "slovak": "sk_SK", "slovaquie": "sk_SK",
    "si": "sl_SI", "slovenia": "sl_SI", "slovenie": "sl_SI",
    "hr": "hr_HR", "croatia": "hr_HR", "croatian": "hr_HR", "croatie": "hr_HR",
    "hu": "hu_HU", "hungary": "hu_HU", "hungarian": "hu_HU", "hongrie": "hu_HU",
    "ro": "ro_RO", "romania": "ro_RO", "romanian": "ro_RO", "roumanie": "ro_RO",
    "bg": "bg_BG", "bulgaria": "bg_BG", "bulgarian": "bg_BG", "bulgarie": "bg_BG",
    "cz": "cs_CZ", "czech": "cs_CZ", "czech republic": "cs_CZ", "czechia": "cs_CZ",
    "ee": "et_EE", "estonia": "et_EE",
    "lv": "lv_LV", "latvia": "lv_LV",
    "lt": "lt_LT", "lithuania": "lt_LT",
}

CIVIL  = ["Single", "Married", "Divorced", "Widowed", "In a relationship"]


def resolve(raw: str):
    locale = ALIASES.get(raw.lower().strip())
    if not locale:
        return None
    name, flag = LOCALES[locale]
    return locale, name, flag


def sf(func) -> str:
    try:
        v = func()
        return str(v) if v else ""
    except Exception:
        return ""


def row(t: Table, label: str, value: str):
    if value:
        t.add_row(f"[bold cyan]{label}[/]", value)


def make_table() -> Table:
    t = Table(show_header=False, box=None, padding=(0, 2, 0, 0))
    t.add_column("k", style="dim", min_width=16, no_wrap=True)
    t.add_column("v", style="white")
    return t


def section(title: str):
    console.print(f"\n[bold white]{title}[/]")
    console.print("[dim]" + "─" * 38 + "[/]")


def generate(locale: str, name: str, flag: str, idx: int, total: int):
    fake = Faker(locale)
    Faker.seed(random.randint(0, 999_999))

    dob    = fake.date_of_birth(minimum_age=18, maximum_age=80)
    age    = (date.today() - dob).days // 365
    _ = fake.local_latlng()  # consume seed step

    counter = f" #{idx}/{total}" if total > 1 else ""
    console.print(f"\n[bold bright_magenta]{flag} {name.upper()}{counter}[/]  [dim]— fake-identity[/]")
    console.print("[bright_magenta]" + "━" * 48 + "[/]")

    section("👤  Identity")
    t = make_table()
    row(t, "Full name",     sf(fake.name))
    row(t, "First name",    sf(fake.first_name))
    row(t, "Last name",     sf(fake.last_name))
    row(t, "Date of birth", f"{dob.strftime('%Y-%m-%d')}  (age {age})")
    row(t, "Gender",        random.choice(["Male", "Female"]))
    row(t, "Civil status",  random.choice(CIVIL))
    row(t, "Children",      str(random.choice([0, 0, 1, 1, 2, 3])))
    console.print(t)

    section("📬  Contact")
    t = make_table()
    row(t, "Address",       sf(fake.address).replace("\n", ", "))
    row(t, "City",          sf(fake.city))
    row(t, "Postcode",      sf(fake.postcode))
    row(t, "Country",       name)
    row(t, "Phone",         sf(fake.phone_number))
    row(t, "Phone 2",       sf(fake.phone_number))
    row(t, "Email",         sf(fake.email))
    row(t, "Email (free)",  sf(fake.free_email))
    row(t, "Email (work)",  sf(fake.company_email))
    row(t, "Website",       sf(fake.url))
    row(t, "Username",      sf(fake.user_name))
    row(t, "Password",      fake.password(length=16, special_chars=True))
    console.print(t)

    section("💳  Finance")
    t = make_table()
    row(t, "IBAN",          sf(lambda: fake.iban()))
    row(t, "BBAN",          sf(lambda: fake.bban()))
    row(t, "SWIFT / BIC",   sf(lambda: fake.swift()))
    row(t, "Card number",   sf(lambda: fake.credit_card_number(card_type=None)))
    row(t, "Card expiry",   sf(lambda: fake.credit_card_expire()))
    row(t, "CVV",           sf(lambda: fake.credit_card_security_code()))
    row(t, "Card network",  sf(lambda: fake.credit_card_provider()))
    row(t, "VAT / Tax ID",  sf(lambda: fake.vat_id()))
    row(t, "SSN",           sf(lambda: fake.ssn()))
    console.print(t)

    section("🪪  IDs & Documents")
    t = make_table()
    row(t, "Passport",      sf(lambda: fake.passport_number()))
    row(t, "License plate", sf(lambda: fake.license_plate()))
    row(t, "SSN (fmt)",     sf(lambda: fake.numerify("##-##-##-###-###-##")))
    row(t, "UUID",          sf(lambda: fake.uuid4()))
    row(t, "MD5",           sf(lambda: fake.md5()))
    row(t, "SHA1",          sf(lambda: fake.sha1()))
    console.print(t)

    console.print("\n[dim]" + "━" * 48 + "[/]")


def main():
    parser = argparse.ArgumentParser(
        prog="fakidity.py",
        description="Generate realistic fake identities for a given country.",
        epilog=(
            "Examples:\n"
            "  python fakidity.py fr\n"
            "  python fakidity.py france --count 3\n"
            "  python fakidity.py 'united states' -n 2\n"
            "  python fakidity.py german\n\n"
            "Accepts: country codes (fr, de, us), names (france, germany),\n"
            "         adjectives (french, german), locale codes (fr_FR)."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("country",
                        help="Country name, 2-letter code, adjective, or locale (e.g. fr / france / french / fr_FR)")
    parser.add_argument("-n", "--count", type=int, default=1, metavar="N",
                        help="Number of identities to generate (default: 1)")
    args = parser.parse_args()

    result = resolve(args.country)
    if not result:
        console.print(f"[bold red]✗[/] Unknown country: [yellow]{args.country}[/]")
        console.print(f"[dim]Supported: {', '.join(sorted(set(ALIASES.keys()))[:30])} …[/]")
        sys.exit(1)

    locale, name, flag = result
    for i in range(1, max(1, args.count) + 1):
        generate(locale, name, flag, i, args.count)


if __name__ == "__main__":
    main()
