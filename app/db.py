import os
import glob
import psycopg2
from psycopg2 import pool
from psycopg2.extras import RealDictCursor

_pool: pool.ThreadedConnectionPool | None = None


def _dsn() -> str:
    return (
        f"host={os.environ['POSTGRES_HOST']} "
        f"port={os.environ.get('POSTGRES_PORT', '5432')} "
        f"dbname={os.environ['POSTGRES_DB']} "
        f"user={os.environ['POSTGRES_USER']} "
        f"password={os.environ['POSTGRES_PASSWORD']}"
    )


def get_pool() -> pool.ThreadedConnectionPool:
    global _pool
    if _pool is None:
        _pool = pool.ThreadedConnectionPool(minconn=1, maxconn=5, dsn=_dsn())
    return _pool


def get_conn():
    """Return a connection from the pool. Caller must call put_conn() when done."""
    return get_pool().getconn()


def put_conn(conn) -> None:
    get_pool().putconn(conn)


def execute(sql: str, params=None, *, fetch: bool = False):
    """Run a single SQL statement, optionally returning rows as dicts."""
    conn = get_conn()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql, params)
            result = cur.fetchall() if fetch else None
        conn.commit()
        return result
    except Exception:
        conn.rollback()
        raise
    finally:
        put_conn(conn)


def health_check() -> bool:
    """Return True if the database is reachable and pgvector is enabled."""
    try:
        rows = execute("SELECT extname FROM pg_extension WHERE extname = 'vector'", fetch=True)
        return len(rows) > 0
    except Exception:
        return False


def run_migrations() -> None:
    """Run all SQL files in sql/migrations/ in filename order. Idempotent."""
    migration_dir = os.path.join(os.path.dirname(__file__), "..", "sql", "migrations")
    files = sorted(glob.glob(os.path.join(migration_dir, "*.sql")))
    if not files:
        raise FileNotFoundError(f"No migration files found in {migration_dir}")
    for path in files:
        print(f"  Running migration: {os.path.basename(path)}")
        with open(path) as f:
            sql = f.read()
        execute(sql)
    print(f"  {len(files)} migration(s) applied.")


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "migrate":
        run_migrations()
    elif len(sys.argv) > 1 and sys.argv[1] == "health":
        ok = health_check()
        print("healthy" if ok else "unhealthy")
        sys.exit(0 if ok else 1)
    else:
        print("Usage: python -m app.db [migrate|health]")
        sys.exit(1)
