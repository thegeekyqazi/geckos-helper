"""Weather from wttr.in (what end-4's bar uses). Location: [desktop] weather_city, else your IP."""

import httpx

from ..config import load_config


def forecast(days: int = 2) -> dict:
    city = load_config()["desktop"].get("weather_city", "")
    r = httpx.get(f"https://wttr.in/{city}", params={"format": "j1"}, timeout=20)
    r.raise_for_status()
    data = r.json()
    area = data["nearest_area"][0]
    cur = data["current_condition"][0]
    return {
        "location": f"{area['areaName'][0]['value']}, {area['region'][0]['value']}",
        "now": {"temp_c": cur["temp_C"], "feels_like_c": cur["FeelsLikeC"],
                "description": cur["weatherDesc"][0]["value"], "precip_mm": cur["precipMM"]},
        "days": [
            {"date": d["date"], "min_c": d["mintempC"], "max_c": d["maxtempC"],
             "hourly": [{"time": f"{int(h['time']) // 100:02d}:00", "temp_c": h["tempC"],
                         "chance_of_rain": h["chanceofrain"], "description": h["weatherDesc"][0]["value"]}
                        for h in d["hourly"]]}
            for d in data["weather"][:days]
        ],
    }
