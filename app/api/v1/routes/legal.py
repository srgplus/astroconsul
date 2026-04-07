from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

router = APIRouter(tags=["legal"])

_templates_dir = Path(__file__).resolve().parents[4] / "templates"
_templates = Jinja2Templates(directory=str(_templates_dir))


@router.get("/legal", response_class=HTMLResponse)
def terms_page(request: Request):
    """Render Terms of Service page."""
    return _templates.TemplateResponse(request=request, name="legal/terms.html")


@router.get("/support", response_class=HTMLResponse)
def support_page(request: Request):
    """Render Contact & Support page."""
    return _templates.TemplateResponse(request=request, name="legal/support.html")
