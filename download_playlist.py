#!/usr/bin/env python3
from __future__ import annotations

"""
Spotify Playlist Downloader — companion script for BingoBite.

Downloads songs from a Spotify playlist using spotdl's Python API,
and generates a master CSV of the full playlist metadata.

Requirements:
    - spotdl (pip install spotdl)
    - Spotify credentials configured in ~/.spotdl/config.json
      (run `spotdl --generate-config` to create it)

Usage:
    python3 download_playlist.py <playlist_url> <songs_dir> [options]

Examples:
    python3 download_playlist.py "https://open.spotify.com/playlist/..." ~/Music/Songs
    python3 download_playlist.py "https://open.spotify.com/playlist/..." ~/Music/Songs --dry-run
    python3 download_playlist.py "https://open.spotify.com/playlist/..." ~/Music/Songs -o metadata.csv -f flac
"""

import argparse
import csv
import json
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from spotdl.download.downloader import Downloader
from spotdl.types.song import Song
from spotdl.utils.config import get_config, SPOTIFY_OPTIONS
from spotdl.utils.formatter import create_file_name
from spotdl.utils.search import get_simple_songs, reinit_song
from spotdl.utils.spotify import SpotifyClient


CSV_COLUMNS = [
    "name",
    "artist",
    "artists",
    "album",
    "album_artist",
    "duration_seconds",
    "duration_formatted",
    "year",
    "release_date",
    "genre",
    "track_number",
    "disc_number",
    "explicit",
    "popularity",
    "isrc",
    "spotify_url",
    "cover_url",
    "publisher",
    "copyright",
    "album_type",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Download a Spotify playlist and generate a metadata CSV."
    )
    parser.add_argument("playlist_url", help="Spotify playlist URL")
    parser.add_argument("songs_dir", help="Directory to download songs into")
    parser.add_argument(
        "-o", "--output-csv", default=None,
        help="Path for the output CSV (default: <songs_dir>/playlist.csv)",
    )
    parser.add_argument(
        "-f", "--format", default="mp3", choices=["mp3", "flac", "ogg", "opus", "m4a", "wav"],
        help="Audio format (default: mp3)",
    )
    parser.add_argument(
        "-t", "--threads", type=int, default=4,
        help="Number of threads for metadata fetching and downloading (default: 4)",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Fetch metadata and write CSV without downloading any songs",
    )
    parser.add_argument(
        "--client-id", default=None,
        help="Spotify client ID (overrides config file)",
    )
    parser.add_argument(
        "--client-secret", default=None,
        help="Spotify client secret (overrides config file)",
    )
    return parser.parse_args()


def init_spotify_client(client_id: str | None, client_secret: str | None) -> None:
    """Initialize the SpotifyClient singleton with credentials."""
    # Try CLI args first, then config file, then built-in defaults
    if client_id and client_secret:
        cid, csecret = client_id, client_secret
    else:
        try:
            config = get_config()
            cid = config.get("client_id", SPOTIFY_OPTIONS["client_id"])
            csecret = config.get("client_secret", SPOTIFY_OPTIONS["client_secret"])
        except Exception:
            cid = SPOTIFY_OPTIONS["client_id"]
            csecret = SPOTIFY_OPTIONS["client_secret"]

    SpotifyClient.init(client_id=cid, client_secret=csecret)


def fetch_full_songs(simple_songs: list[Song], threads: int) -> list[Song]:
    """Reinitialize songs with full metadata using parallel threads."""
    full_songs: list[Song] = []
    failed = 0
    total = len(simple_songs)

    print(f"Fetching full metadata for {total} songs ({threads} threads)...")

    with ThreadPoolExecutor(max_workers=threads) as executor:
        futures = {
            executor.submit(reinit_song, song): i
            for i, song in enumerate(simple_songs)
        }
        for future in as_completed(futures):
            idx = futures[future]
            try:
                full_song = future.result()
                full_songs.append(full_song)
            except Exception as exc:
                failed += 1
                name = simple_songs[idx].name or "Unknown"
                print(f"  Warning: failed to fetch metadata for '{name}': {exc}")

    # Preserve original playlist order
    url_to_song = {s.url: s for s in full_songs}
    ordered = [url_to_song[s.url] for s in simple_songs if s.url in url_to_song]

    print(f"  Fetched {len(ordered)} of {total} songs" +
          (f" ({failed} failed)" if failed else ""))
    return ordered


def detect_existing(songs: list[Song], songs_dir: Path, fmt: str) -> tuple[list[Song], list[Song]]:
    """Split songs into (existing, missing) based on expected filenames."""
    existing = []
    missing = []
    output_template = str(songs_dir) + "/{artists} - {title}.{output-ext}"

    for song in songs:
        expected_path = create_file_name(
            song=song,
            template=output_template,
            file_extension=fmt,
        )
        if expected_path.exists():
            existing.append(song)
        else:
            missing.append(song)

    return existing, missing


def download_songs(
    songs: list[Song], songs_dir: Path, fmt: str, threads: int
) -> list[tuple[Song, Path | None]]:
    """Download songs using spotdl's Downloader."""
    output_template = str(songs_dir) + "/{artists} - {title}.{output-ext}"

    downloader = Downloader(settings={
        "output": output_template,
        "format": fmt,
        "threads": threads,
        "overwrite": "skip",
        "simple_tui": True,
        "log_level": "INFO",
    })

    results = downloader.download_multiple_songs(songs)
    return results


def format_duration(seconds: int) -> str:
    """Format seconds as M:SS or H:MM:SS."""
    if seconds < 0:
        seconds = 0
    hours, remainder = divmod(seconds, 3600)
    minutes, secs = divmod(remainder, 60)
    if hours > 0:
        return f"{hours}:{minutes:02d}:{secs:02d}"
    return f"{minutes}:{secs:02d}"


def song_to_csv_row(song: Song) -> dict:
    """Convert a Song object to a CSV row dict."""
    return {
        "name": song.name,
        "artist": song.artist,
        "artists": "; ".join(song.artists) if song.artists else song.artist,
        "album": song.album_name,
        "album_artist": song.album_artist,
        "duration_seconds": song.duration,
        "duration_formatted": format_duration(song.duration),
        "year": song.year,
        "release_date": song.date,
        "genre": "; ".join(song.genres) if song.genres else "",
        "track_number": song.track_number,
        "disc_number": song.disc_number,
        "explicit": song.explicit,
        "popularity": song.popularity,
        "isrc": song.isrc or "",
        "spotify_url": song.url,
        "cover_url": song.cover_url or "",
        "publisher": song.publisher,
        "copyright": song.copyright_text or "",
        "album_type": song.album_type or "",
    }


def write_csv(songs: list[Song], csv_path: Path) -> None:
    """Write all songs to a CSV file."""
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=CSV_COLUMNS)
        writer.writeheader()
        for song in songs:
            writer.writerow(song_to_csv_row(song))
    print(f"CSV written to {csv_path} ({len(songs)} songs)")


def main() -> None:
    args = parse_args()

    songs_dir = Path(args.songs_dir).expanduser().resolve()
    songs_dir.mkdir(parents=True, exist_ok=True)

    csv_path = Path(args.output_csv) if args.output_csv else songs_dir / "playlist.csv"
    csv_path = csv_path.expanduser().resolve()

    # 1. Initialize Spotify client
    print("Initializing Spotify client...")
    init_spotify_client(args.client_id, args.client_secret)

    # 2. Fetch playlist track list
    print(f"Fetching playlist tracks from: {args.playlist_url}")
    simple_songs = get_simple_songs([args.playlist_url])
    print(f"  Found {len(simple_songs)} tracks")

    if not simple_songs:
        print("No songs found in playlist. Exiting.")
        sys.exit(1)

    # 3. Fetch full metadata in parallel
    songs = fetch_full_songs(simple_songs, args.threads)

    if not songs:
        print("Failed to fetch metadata for any songs. Exiting.")
        sys.exit(1)

    # 4. Write CSV (always, regardless of --dry-run)
    write_csv(songs, csv_path)

    # 5. Download missing songs (unless --dry-run)
    if args.dry_run:
        print("Dry run — skipping downloads.")
    else:
        existing, missing = detect_existing(songs, songs_dir, args.format)
        print(f"{len(existing)} songs already present, {len(missing)} to download")

        if missing:
            print(f"Downloading {len(missing)} songs...")
            results = download_songs(missing, songs_dir, args.format, args.threads)
            downloaded = sum(1 for _, path in results if path is not None)
            failed = len(results) - downloaded
            print(f"  Downloaded {downloaded} songs" +
                  (f" ({failed} failed)" if failed else ""))
        else:
            print("All songs already present — nothing to download.")

    print("Done.")


if __name__ == "__main__":
    main()
