import logging
import sys
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import JSONResponse

from app.config import settings
from app.core.session_manager import SessionManager
from pathlib import Path
from fastapi.staticfiles import StaticFiles
from app.routers import sessions, calls, ws as ws_router, lobby as lobby_router, chat as chat_router, users as users_router
from app.core.database import init_db, close_db

logging.basicConfig(
    level=logging.DEBUG if settings.DEBUG else logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger(__name__)

session_manager = SessionManager()


@asynccontextmanager
async def lifespan(app: FastAPI):
    await session_manager.initialize()
    sessions.set_session_manager(session_manager)
    calls.set_session_manager(session_manager)
    ws_router.set_session_manager(session_manager)
    lobby_router.set_session_manager(session_manager)
    chat_router.set_session_manager(session_manager)
    await init_db()
    logger.info(f"Voice Translation Platform v{settings.APP_VERSION} started")
    yield
    await session_manager.cleanup()
    await close_db()
    logger.info("Shutdown complete")


app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description=(
        "Real-time bidirectional voice translation platform. "
        "Enables seamless multilingual conversations via WebSocket streaming."
    ),
    lifespan=lifespan,
    docs_url="/api/docs",
    redoc_url="/api/redoc",
    openapi_url="/api/openapi.json",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(GZipMiddleware, minimum_size=1000)

app.include_router(users_router.router, prefix="/api/users", tags=["Users"])
app.include_router(sessions.router, prefix="/api/sessions", tags=["Sessions"])
app.include_router(calls.router, prefix="/api/telephony", tags=["Telephony"])
app.include_router(ws_router.router, tags=["WebSocket"])
app.include_router(lobby_router.router, tags=["Lobby"])
app.include_router(chat_router.router, prefix="/api/sessions", tags=["Chat"])

# Serve uploaded files
_upload_dir = Path("/app/uploads")
_upload_dir.mkdir(parents=True, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=str(_upload_dir)), name="uploads")


@app.get("/health", tags=["Health"])
async def health():
    return {
        "status": "healthy",
        "version": settings.APP_VERSION,
        "tts_provider": settings.TTS_PROVIDER,
    }


@app.get("/api/languages", tags=["Config"])
async def get_supported_languages():
    from app.models.session import LANGUAGE_NAMES
    return {
        "languages": [
            {"code": code, "name": name}
            for code, name in LANGUAGE_NAMES.items()
        ]
    }


@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    logger.error(f"Unhandled exception: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error"},
    )
