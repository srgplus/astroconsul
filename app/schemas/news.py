from __future__ import annotations

from datetime import date, datetime

from pydantic import BaseModel


class NewsPostSummary(BaseModel):
    slug: str
    title: str
    subtitle: str | None = None
    date: date
    author: str
    intro: str
    tags: list[str] = []
    hero_image_url: str | None = None

    class Config:
        from_attributes = True


class NewsSection(BaseModel):
    heading: str
    body: str
    image_url: str | None = None
    image_alt: str | None = None


class NewsPostDetail(BaseModel):
    slug: str
    title: str
    subtitle: str | None = None
    date: date
    author: str
    status: str
    intro: str
    sections: list[NewsSection] = []
    conclusion: str | None = None
    celebrity_name: str | None = None
    celebrity_event: str | None = None
    meta_title: str | None = None
    meta_description: str | None = None
    keywords: list[str] = []
    og_image_url: str | None = None
    tags: list[str] = []
    hero_image_url: str | None = None
    published_at: datetime | None = None

    class Config:
        from_attributes = True
