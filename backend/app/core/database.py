import asyncpg
import logging
from app.config import settings

logger = logging.getLogger(__name__)

_pool: asyncpg.Pool | None = None


async def init_db():
    global _pool
    try:
        _pool = await asyncpg.create_pool(
            settings.DATABASE_URL.replace("+asyncpg", ""),
            min_size=2,
            max_size=10,
        )
        async with _pool.acquire() as conn:
            await conn.execute("""
                CREATE TABLE IF NOT EXISTS users (
                    phone       TEXT PRIMARY KEY,
                    name        TEXT NOT NULL,
                    language    TEXT NOT NULL DEFAULT 'en',
                    fcm_token   TEXT,
                    is_online   BOOLEAN DEFAULT FALSE,
                    last_seen   TIMESTAMPTZ DEFAULT NOW()
                );
                CREATE TABLE IF NOT EXISTS chat_messages (
                    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    session_id  TEXT NOT NULL,
                    participant_id   TEXT NOT NULL,
                    participant_name TEXT NOT NULL,
                    message_type TEXT NOT NULL,
                    content     TEXT,
                    file_url    TEXT,
                    file_name   TEXT,
                    mime_type   TEXT,
                    duration_ms INTEGER,
                    created_at  TIMESTAMPTZ DEFAULT NOW()
                );
                CREATE INDEX IF NOT EXISTS idx_chat_sess
                    ON chat_messages(session_id, created_at);
                CREATE TABLE IF NOT EXISTS direct_messages (
                    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    sender_phone    TEXT NOT NULL,
                    receiver_phone  TEXT NOT NULL,
                    content         TEXT,
                    message_type    TEXT NOT NULL DEFAULT 'text',
                    file_url        TEXT,
                    file_name       TEXT,
                    mime_type       TEXT,
                    duration_ms     INTEGER,
                    is_read         BOOLEAN DEFAULT FALSE,
                    created_at      TIMESTAMPTZ DEFAULT NOW()
                );
                CREATE INDEX IF NOT EXISTS idx_dm_pair
                    ON direct_messages(sender_phone, receiver_phone, created_at);
                CREATE INDEX IF NOT EXISTS idx_dm_receiver
                    ON direct_messages(receiver_phone, created_at);
                ALTER TABLE direct_messages ALTER COLUMN content DROP NOT NULL;
                ALTER TABLE direct_messages ADD COLUMN IF NOT EXISTS message_type TEXT NOT NULL DEFAULT 'text';
                ALTER TABLE direct_messages ADD COLUMN IF NOT EXISTS file_url TEXT;
                ALTER TABLE direct_messages ADD COLUMN IF NOT EXISTS file_name TEXT;
                ALTER TABLE direct_messages ADD COLUMN IF NOT EXISTS mime_type TEXT;
                ALTER TABLE direct_messages ADD COLUMN IF NOT EXISTS duration_ms INTEGER;
            """)
        logger.info("Database initialized")
    except Exception as e:
        logger.warning(f"Database unavailable: {e}")
        _pool = None


async def close_db():
    global _pool
    if _pool:
        await _pool.close()
        _pool = None


def get_pool() -> asyncpg.Pool | None:
    return _pool


async def upsert_user(phone: str, name: str, language: str, fcm_token: str | None = None) -> dict | None:
    pool = get_pool()
    if not pool:
        return None
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            """
            INSERT INTO users (phone, name, language, fcm_token, is_online, last_seen)
            VALUES ($1, $2, $3, $4, TRUE, NOW())
            ON CONFLICT (phone) DO UPDATE
                SET name = EXCLUDED.name,
                    language = EXCLUDED.language,
                    fcm_token = COALESCE(EXCLUDED.fcm_token, users.fcm_token),
                    is_online = TRUE,
                    last_seen = NOW()
            RETURNING phone, name, language, fcm_token, is_online, last_seen
            """,
            phone, name, language, fcm_token,
        )
        return dict(row) if row else None


async def get_user(phone: str) -> dict | None:
    pool = get_pool()
    if not pool:
        return None
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            "SELECT phone, name, language, fcm_token, is_online, last_seen FROM users WHERE phone = $1",
            phone,
        )
        return dict(row) if row else None


async def set_user_online(phone: str, is_online: bool) -> None:
    pool = get_pool()
    if not pool:
        return
    async with pool.acquire() as conn:
        await conn.execute(
            "UPDATE users SET is_online = $1, last_seen = NOW() WHERE phone = $2",
            is_online, phone,
        )


async def update_fcm_token(phone: str, fcm_token: str) -> None:
    pool = get_pool()
    if not pool:
        return
    async with pool.acquire() as conn:
        await conn.execute(
            "UPDATE users SET fcm_token = $1 WHERE phone = $2",
            fcm_token, phone,
        )


async def save_message(
    session_id: str,
    participant_id: str,
    participant_name: str,
    message_type: str,
    content: str | None = None,
    file_url: str | None = None,
    file_name: str | None = None,
    mime_type: str | None = None,
    duration_ms: int | None = None,
) -> dict | None:
    pool = get_pool()
    if not pool:
        return None
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            """
            INSERT INTO chat_messages
                (session_id, participant_id, participant_name, message_type,
                 content, file_url, file_name, mime_type, duration_ms)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            RETURNING id, created_at
            """,
            session_id, participant_id, participant_name, message_type,
            content, file_url, file_name, mime_type, duration_ms,
        )
        if row:
            return {
                "id": str(row["id"]),
                "session_id": session_id,
                "participant_id": participant_id,
                "participant_name": participant_name,
                "message_type": message_type,
                "content": content,
                "file_url": file_url,
                "file_name": file_name,
                "mime_type": mime_type,
                "duration_ms": duration_ms,
                "created_at": row["created_at"].isoformat(),
            }
    return None


async def get_messages(session_id: str, limit: int = 100) -> list[dict]:
    pool = get_pool()
    if not pool:
        return []
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT id, session_id, participant_id, participant_name,
                   message_type, content, file_url, file_name, mime_type,
                   duration_ms, created_at
            FROM chat_messages
            WHERE session_id = $1
            ORDER BY created_at ASC
            LIMIT $2
            """,
            session_id, limit,
        )
        return [
            {
                "id": str(r["id"]),
                "session_id": r["session_id"],
                "participant_id": r["participant_id"],
                "participant_name": r["participant_name"],
                "message_type": r["message_type"],
                "content": r["content"],
                "file_url": r["file_url"],
                "file_name": r["file_name"],
                "mime_type": r["mime_type"],
                "duration_ms": r["duration_ms"],
                "created_at": r["created_at"].isoformat(),
            }
            for r in rows
        ]


async def save_direct_message(
    sender_phone: str,
    receiver_phone: str,
    content: str | None = None,
    message_type: str = "text",
    file_url: str | None = None,
    file_name: str | None = None,
    mime_type: str | None = None,
    duration_ms: int | None = None,
) -> dict | None:
    pool = get_pool()
    if not pool:
        return None
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            """
            INSERT INTO direct_messages
                (sender_phone, receiver_phone, content, message_type,
                 file_url, file_name, mime_type, duration_ms)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            RETURNING id, sender_phone, receiver_phone, content, message_type,
                      file_url, file_name, mime_type, duration_ms, is_read, created_at
            """,
            sender_phone, receiver_phone, content, message_type,
            file_url, file_name, mime_type, duration_ms,
        )
        if row:
            return {
                "id": str(row["id"]),
                "sender_phone": row["sender_phone"],
                "receiver_phone": row["receiver_phone"],
                "content": row["content"],
                "message_type": row["message_type"],
                "file_url": row["file_url"],
                "file_name": row["file_name"],
                "mime_type": row["mime_type"],
                "duration_ms": row["duration_ms"],
                "is_read": row["is_read"],
                "created_at": row["created_at"].isoformat(),
            }
    return None


async def get_direct_messages(me: str, other: str, limit: int = 100) -> list[dict]:
    pool = get_pool()
    if not pool:
        return []
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT id, sender_phone, receiver_phone, content, message_type,
                   file_url, file_name, mime_type, duration_ms, is_read, created_at
            FROM direct_messages
            WHERE (sender_phone = $1 AND receiver_phone = $2)
               OR (sender_phone = $2 AND receiver_phone = $1)
            ORDER BY created_at ASC
            LIMIT $3
            """,
            me, other, limit,
        )
        # Mark messages to me as read
        await conn.execute(
            "UPDATE direct_messages SET is_read = TRUE WHERE receiver_phone = $1 AND sender_phone = $2 AND is_read = FALSE",
            me, other,
        )
        return [
            {
                "id": str(r["id"]),
                "sender_phone": r["sender_phone"],
                "receiver_phone": r["receiver_phone"],
                "content": r["content"],
                "message_type": r["message_type"],
                "file_url": r["file_url"],
                "file_name": r["file_name"],
                "mime_type": r["mime_type"],
                "duration_ms": r["duration_ms"],
                "is_read": r["is_read"],
                "created_at": r["created_at"].isoformat(),
            }
            for r in rows
        ]


async def get_conversations(phone: str) -> list[dict]:
    """Return last message for each unique conversation partner."""
    pool = get_pool()
    if not pool:
        return []
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT DISTINCT ON (other_phone)
                other_phone,
                content AS last_message,
                created_at,
                unread_count
            FROM (
                SELECT
                    CASE WHEN sender_phone = $1 THEN receiver_phone ELSE sender_phone END AS other_phone,
                    content,
                    created_at,
                    (SELECT COUNT(*) FROM direct_messages d2
                     WHERE d2.receiver_phone = $1
                       AND d2.sender_phone = CASE WHEN dm.sender_phone = $1 THEN dm.receiver_phone ELSE dm.sender_phone END
                       AND d2.is_read = FALSE) AS unread_count
                FROM direct_messages dm
                WHERE sender_phone = $1 OR receiver_phone = $1
                ORDER BY created_at DESC
            ) sub
            ORDER BY other_phone, created_at DESC
            """,
            phone,
        )
        # Get user info for each partner
        result = []
        for r in rows:
            user = await get_user(r["other_phone"])
            result.append({
                "other_phone": r["other_phone"],
                "other_name": user["name"] if user else r["other_phone"],
                "other_language": user["language"] if user else "en",
                "last_message": r["last_message"],
                "created_at": r["created_at"].isoformat(),
                "unread_count": r["unread_count"],
            })
        result.sort(key=lambda x: x["created_at"], reverse=True)
        return result
