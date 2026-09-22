"""POSIX の非同期シグナル安全な関数の一覧に mutex のロックが含まれるかを見る。"""
import html
import pathlib
import re

body = html.unescape(re.sub(r"<[^>]+>", " ", pathlib.Path("posix.html").read_text(errors="replace")))
for name in ["pthread_mutex_lock", "pthread_mutex_unlock", "pthread_mutex_trylock", "pthread_mutex"]:
    print(f"  {name}: {name in body}")
for name in ["write(", "sigaction(", "_Exit("]:
    print(f"  対照 {name}: {name in body}")
