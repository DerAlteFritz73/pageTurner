#!/usr/bin/env python3
"""
Export IMSLP data from MariaDB (continuo project) to a SQLite database
for bundling with the Leggio Flutter app.

Usage:
    python export_imslp_sqlite.py [--host HOST] [--port PORT] [--user USER]
                                  [--password PASSWORD] [--database DATABASE]
                                  [--output OUTPUT]

Defaults match the continuo .env: mysql://continuo:continuo@127.0.0.1:3306/continuo
"""

import argparse
import gzip
import os
import shutil
import sqlite3
import sys

try:
    import mysql.connector
except ImportError:
    sys.exit("pip install mysql-connector-python")


def create_sqlite_schema(cur: sqlite3.Cursor) -> None:
    cur.executescript("""
        CREATE TABLE IF NOT EXISTS imslp_composer (
            id INTEGER PRIMARY KEY,
            imslp_id TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            permlink TEXT NOT NULL,
            born_year INTEGER,
            died_year INTEGER,
            nationality TEXT,
            time_period TEXT,
            synced_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_composer_name
            ON imslp_composer(name);

        CREATE TABLE IF NOT EXISTS imslp_work (
            id INTEGER PRIMARY KEY,
            imslp_id TEXT NOT NULL UNIQUE,
            title TEXT NOT NULL,
            composer TEXT NOT NULL,
            catalog_number TEXT NOT NULL DEFAULT '',
            page_id INTEGER NOT NULL,
            permlink TEXT NOT NULL,
            work_key TEXT,
            instrumentation TEXT,
            piece_style TEXT,
            year_composed TEXT,
            year_composed_int INTEGER,
            year_published TEXT,
            tags TEXT,
            page_type TEXT,
            movements TEXT,
            genre_cats TEXT,
            language TEXT,
            alternative_title TEXT,
            average_duration TEXT,
            librettist TEXT,
            dedication TEXT,
            first_performance TEXT,
            composer_id INTEGER,
            duration_seconds INTEGER,
            first_perf_date TEXT,
            first_perf_location TEXT,
            files_json TEXT,
            detail_synced_at TEXT,
            synced_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_work_composer
            ON imslp_work(composer);
        CREATE INDEX IF NOT EXISTS idx_work_page_id
            ON imslp_work(page_id);
        CREATE INDEX IF NOT EXISTS idx_work_style
            ON imslp_work(piece_style);
        CREATE INDEX IF NOT EXISTS idx_work_year
            ON imslp_work(year_composed_int);

        CREATE TABLE IF NOT EXISTS imslp_edition (
            id INTEGER PRIMARY KEY,
            work_id INTEGER NOT NULL,
            page_id INTEGER NOT NULL,
            image_type TEXT,
            url TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_edition_work
            ON imslp_edition(work_id);

        CREATE VIRTUAL TABLE IF NOT EXISTS imslp_work_fts USING fts5(
            title,
            composer,
            catalog_number,
            alternative_title,
            instrumentation,
            tags,
            genre_cats,
            content='imslp_work',
            content_rowid='id'
        );
    """)


def export_composers(mcur, scur) -> int:
    mcur.execute("""
        SELECT id, imslp_id, name, permlink, born_year, died_year,
               nationality, time_period, synced_at
        FROM imslp_composer ORDER BY id
    """)
    rows = mcur.fetchall()
    scur.executemany(
        "INSERT INTO imslp_composer VALUES (?,?,?,?,?,?,?,?,?)",
        [(r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7],
          str(r[8]) if r[8] else '') for r in rows],
    )
    return len(rows)


def export_works(mcur, scur) -> int:
    mcur.execute("""
        SELECT id, imslp_id, title, composer, catalog_number, page_id,
               permlink, work_key, instrumentation, piece_style,
               year_composed, year_composed_int, year_published, tags,
               page_type, movements, genre_cats, language, alternative_title,
               average_duration, librettist, dedication, first_performance,
               composer_id, duration_seconds, first_perf_date,
               first_perf_location, files_json, detail_synced_at, synced_at
        FROM imslp_work ORDER BY id
    """)

    count = 0
    batch = []
    for row in mcur:
        converted = []
        for i, val in enumerate(row):
            if val is None:
                converted.append(None)
            elif isinstance(val, (bytes, bytearray)):
                converted.append(val.decode("utf-8", errors="replace"))
            elif hasattr(val, "isoformat"):
                converted.append(str(val))
            else:
                converted.append(val)
        batch.append(tuple(converted))
        count += 1
        if len(batch) >= 5000:
            scur.executemany(
                "INSERT INTO imslp_work VALUES "
                f"({','.join('?' * 30)})",
                batch,
            )
            batch.clear()

    if batch:
        scur.executemany(
            f"INSERT INTO imslp_work VALUES ({','.join('?' * 30)})",
            batch,
        )
    return count


def export_editions(mcur, scur) -> int:
    mcur.execute("""
        SELECT id, work_id, page_id, image_type, url
        FROM imslp_edition ORDER BY id
    """)
    rows = mcur.fetchall()
    scur.executemany(
        "INSERT INTO imslp_edition VALUES (?,?,?,?,?)",
        rows,
    )
    return len(rows)


def populate_fts(scur) -> None:
    scur.execute("""
        INSERT INTO imslp_work_fts(rowid, title, composer, catalog_number,
                                   alternative_title, instrumentation,
                                   tags, genre_cats)
        SELECT id, title, composer, catalog_number,
               COALESCE(alternative_title, ''),
               COALESCE(instrumentation, ''),
               COALESCE(tags, ''),
               COALESCE(genre_cats, '')
        FROM imslp_work
    """)


def main():
    parser = argparse.ArgumentParser(description="Export IMSLP MariaDB → SQLite")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=3306)
    parser.add_argument("--user", default="continuo")
    parser.add_argument("--password", default="continuo")
    parser.add_argument("--database", default="continuo")
    parser.add_argument("--output", default="imslp.db")
    parser.add_argument("--gzip", action="store_true", help="Also create .db.gz")
    args = parser.parse_args()

    if os.path.exists(args.output):
        os.remove(args.output)

    print(f"Connecting to MariaDB {args.user}@{args.host}:{args.port}/{args.database}")
    mconn = mysql.connector.connect(
        host=args.host,
        port=args.port,
        user=args.user,
        password=args.password,
        database=args.database,
    )
    mcur = mconn.cursor()

    sconn = sqlite3.connect(args.output)
    sconn.execute("PRAGMA journal_mode=WAL")
    sconn.execute("PRAGMA synchronous=OFF")
    scur = sconn.cursor()

    print("Creating schema...")
    create_sqlite_schema(scur)
    sconn.commit()

    print("Exporting composers...")
    n = export_composers(mcur, scur)
    sconn.commit()
    print(f"  {n} composers")

    print("Exporting works...")
    n = export_works(mcur, scur)
    sconn.commit()
    print(f"  {n} works")

    print("Exporting editions...")
    n = export_editions(mcur, scur)
    sconn.commit()
    print(f"  {n} editions")

    print("Building FTS5 index...")
    populate_fts(scur)
    sconn.commit()

    print("Optimizing...")
    sconn.execute("PRAGMA journal_mode=DELETE")
    sconn.execute("VACUUM")
    sconn.commit()

    sconn.close()
    mcur.close()
    mconn.close()

    size_mb = os.path.getsize(args.output) / (1024 * 1024)
    print(f"\nExported to {args.output} ({size_mb:.1f} MB)")

    if args.gzip:
        gz_path = args.output + ".gz"
        with open(args.output, "rb") as f_in:
            with gzip.open(gz_path, "wb", compresslevel=9) as f_out:
                shutil.copyfileobj(f_in, f_out)
        gz_mb = os.path.getsize(gz_path) / (1024 * 1024)
        print(f"Compressed to {gz_path} ({gz_mb:.1f} MB)")

    print("\nTo bundle with Leggio, copy the .db file to assets/db/imslp.db")


if __name__ == "__main__":
    main()
